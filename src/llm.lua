local M = {}

-- Helper to prepare context
function M.prepare_messages(messages, chunks, memories)
    local system_context = ""

    -- Add memories first
    if memories and #memories > 0 then
        system_context = system_context .. "PROJECT MEMORY (Past Decisions):\n"
        for _, mem in ipairs(memories) do
            system_context = system_context .. "• " .. mem.content:sub(1, 300) .. "\n"
        end
        system_context = system_context .. "\n"
    end

    -- Add document context
    if chunks and #chunks > 0 then
        system_context = system_context .. "CONTEXT DOCUMENTS:\n"
        for _, chunk in ipairs(chunks) do
            system_context = system_context .. "---\n"
            if chunk.label then system_context = system_context .. "Section: " .. chunk.label .. "\n" end
            system_context = system_context .. chunk.content .. "\n"
        end
    end

    local new_messages = {}
    local has_system = false

    for _, msg in ipairs(messages) do
        if msg.role == "system" then
            table.insert(new_messages, {
                role = "system",
                content = msg.content .. "\n\n" .. system_context
            })
            has_system = true
        else
            table.insert(new_messages, msg)
        end
    end

    if not has_system then
        table.insert(new_messages, 1, {
            role = "system",
            content = "You are a helpful collaborative peer working on this project.\n\n" .. system_context
        })
    end

    return new_messages
end

function M.generate(peer, messages, chunks, memories)
    if peer.provider == "mock" then
        return {
            content = "This is a MOCK response from " .. peer.name .. ".\nI received " .. #chunks .. " chunks of context."
        }
    elseif peer.provider == "ollama" then
        return M.call_ollama(peer, messages, chunks, memories)
    else
        -- Default to OpenAI compatible (covers openai, lmstudio, nanogpt, etc)
        return M.call_openai(peer, messages, chunks, memories)
    end
end

function M.call_ollama(peer, messages, chunks, memories)
    local full_messages = M.prepare_messages(messages, chunks, memories)
    local payload = {
        model = peer.model_id or peer.model,
        messages = full_messages,
        stream = false,
        options = {
            num_ctx = peer.context_window or 4096
        }
    }

    local url = (peer.base_url or "http://localhost:11434") .. "/api/chat"
    local status, headers, body = Fetch(url, {
        method = "POST",
        body = EncodeJson(payload),
        headers = {["Content-Type"] = "application/json"}
    })

    if status ~= 200 then
        return { error = "Ollama API Error: " .. tostring(status) }
    end

    local ok, response = pcall(DecodeJson, body)
    if not ok then return { error = "Invalid JSON response" } end
    return { content = response.message.content }
end

function M.call_openai(peer, messages, chunks, memories)
    local full_messages = M.prepare_messages(messages, chunks, memories)
    local payload = {
        model = peer.model_id or peer.model,
        messages = full_messages
    }

    -- Normalize base_url
    local base_url = peer.base_url or "https://api.openai.com"
    base_url = base_url:gsub("/+$", "")
    local url = base_url .. "/v1/chat/completions"

    local req_headers = {
        ["Content-Type"] = "application/json"
    }
    if peer.api_key and peer.api_key ~= "" then
        req_headers["Authorization"] = "Bearer " .. peer.api_key
    end

    local status, headers, body = Fetch(url, {
        method = "POST",
        body = EncodeJson(payload),
        headers = req_headers
    })

    if status ~= 200 then
        return { error = "API Error: " .. tostring(status) .. " " .. tostring(body) }
    end

    local ok, response = pcall(DecodeJson, body)
    if not ok then return { error = "Invalid JSON response" } end

    if response.choices and response.choices[1] then
        return { content = response.choices[1].message.content }
    else
        return { error = "Invalid response format" }
    end
end

return M
