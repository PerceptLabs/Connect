local sqlite3 = require("lsqlite3")
local db_mod = require("src.db")
local tokenizer = require("src.tokenizer")

local M = {}

function M.summarize_thread(db, thread_id, peer)
    -- Get thread info
    local thread = nil
    local stmt = db:prepare("SELECT * FROM threads WHERE id = ?")
    stmt:bind_values(thread_id)
    if stmt:step() == sqlite3.ROW then
        thread = stmt:get_named_values()
    end
    stmt:finalize()
    if not thread then return nil, "Thread not found" end

    -- Get last 50 messages
    local messages = {}
    stmt = db:prepare([[
        SELECT role, content FROM messages
        WHERE thread_id = ? ORDER BY created_at DESC LIMIT 50
    ]])
    stmt:bind_values(thread_id)
    for row in stmt:nrows() do
        table.insert(messages, 1, row)
    end
    stmt:finalize()
    if #messages == 0 then return nil, "No messages" end

    -- Build prompt
    local prompt = [[Summarize the key technical decisions from this conversation.
Format as bullet points. Include:
- Decisions made and WHY
- Problems solved
- Unresolved issues

Conversation:
]]
    for _, msg in ipairs(messages) do
        prompt = prompt .. "\n[" .. msg.role .. "]: " .. msg.content:sub(1, 500)
    end

    -- Generate summary
    local llm_mod = require("src.llm")
    local result = llm_mod.generate(peer, {{role = "user", content = prompt}}, {})
    if not result or not result.content then
        return nil, "LLM generation failed"
    end

    -- Store memory
    local memory_id = db_mod.uuid()
    stmt = db:prepare([[
        INSERT INTO memories (id, workspace_id, thread_id, content, memory_type)
        VALUES (?, ?, ?, ?, ?)
    ]])
    stmt:bind_values(memory_id, thread.workspace_id, thread_id, result.content, "decision")
    stmt:step()
    stmt:finalize()

    return { id = memory_id, content = result.content }
end

function M.get_relevant(db, workspace_id, query, limit)
    limit = limit or 5
    local memories = {}

    local sql = [[
        SELECT id, content, memory_type, created_at
        FROM memories WHERE workspace_id = ?
    ]]

    if query and query ~= "" then
        sql = sql .. " AND content LIKE ?"
    end
    sql = sql .. " ORDER BY created_at DESC LIMIT ?"

    local stmt = db:prepare(sql)
    if query and query ~= "" then
        stmt:bind_values(workspace_id, "%" .. query .. "%", limit)
    else
        stmt:bind_values(workspace_id, limit)
    end

    for row in stmt:nrows() do
        table.insert(memories, row)
    end
    stmt:finalize()
    return memories
end

function M.list(db, workspace_id)
    local memories = {}
    local stmt = db:prepare([[
        SELECT m.id, m.content, m.memory_type, m.created_at, t.name as thread_name
        FROM memories m
        LEFT JOIN threads t ON m.thread_id = t.id
        WHERE m.workspace_id = ?
        ORDER BY m.created_at DESC
    ]])
    stmt:bind_values(workspace_id)
    for row in stmt:nrows() do
        table.insert(memories, row)
    end
    stmt:finalize()
    return memories
end

function M.delete(db, memory_id)
    local stmt = db:prepare("DELETE FROM memories WHERE id = ?")
    stmt:bind_values(memory_id)
    stmt:step()
    stmt:finalize()
    return true
end

return M
