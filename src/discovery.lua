local M = {}

function M.discover(provider, base_url, api_key)
    local models = {}
    local url = ""
    local headers = {["Content-Type"] = "application/json"}

    -- Normalize base_url (remove trailing slash)
    base_url = base_url:gsub("/+$", "")

    if provider == "ollama" then
        url = base_url .. "/api/tags"
    elseif provider == "openai" or provider == "lmstudio" or provider == "nanogpt" or provider == "anthropic" then
        -- Anthropic uses different endpoint usually (/v1/messages is chat, /v1/models? maybe)
        -- But for now assume OpenAI compatible logic for list models or fallback.
        -- Anthropic API doesn't have a standard "list models" endpoint like OpenAI in older versions,
        -- but many proxies provide it. We'll assume standard OpenAI shape for "openai"/"lmstudio".
        url = base_url .. "/v1/models"
        if api_key and api_key ~= "" then
            headers["Authorization"] = "Bearer " .. api_key
        end
    else
        return { error = "Unknown provider for discovery" }
    end

    local status, resp_headers, body = Fetch(url, {
        method = "GET",
        headers = headers
    })

    if status ~= 200 then
        return { error = "Discovery failed: " .. tostring(status) }
    end

    local ok, data = pcall(DecodeJson, body)
    if not ok or not data then return { error = "Invalid JSON response" } end

    if provider == "ollama" then
        -- Ollama: { models: [ { name: "llama3:latest", ... } ] }
        if data.models then
            for _, m in ipairs(data.models) do
                table.insert(models, { id = m.name, name = m.name })
            end
        end
    else
        -- OpenAI: { data: [ { id: "gpt-4", ... } ] }
        if data.data then
            for _, m in ipairs(data.data) do
                table.insert(models, { id = m.id, name = m.id })
            end
        end
    end

    return { status = "healthy", models = models }
end

return M
