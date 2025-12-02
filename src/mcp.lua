local sqlite3 = require("lsqlite3")
local db_mod = require("src.db")
local docs_mod = require("src.docs")
local websocket_mod = require("src.websocket")

local M = {}

-- JSON-RPC 2.0 Helpers
local function rpc_result(id, result)
    return { jsonrpc = "2.0", id = id, result = result }
end

local function rpc_error(id, code, message)
    return { jsonrpc = "2.0", id = id, error = { code = code, message = message } }
end

-- Error Codes
local ERR_PARSE = -32700
local ERR_INVALID_REQUEST = -32600
local ERR_METHOD_NOT_FOUND = -32601
local ERR_INTERNAL = -32603

-- Tool: list_files
function M.list_files(db, params)
    local workspace_id = params.workspace_id
    if not workspace_id then return nil, "workspace_id required" end

    local files = {}
    local stmt = db:prepare([[
        SELECT d.id, d.file_path, d.updated_at,
               LENGTH(v.content) as size, v.version_number
        FROM documents d
        LEFT JOIN document_versions v ON d.current_version_id = v.id
        WHERE d.workspace_id = ?
        ORDER BY d.file_path
    ]])
    stmt:bind_values(workspace_id)
    for row in stmt:nrows() do
        table.insert(files, {
            id = row.id,
            path = row.file_path,
            size = row.size or 0,
            version = row.version_number or 0,
            updated_at = row.updated_at
        })
    end
    stmt:finalize()
    return { files = files }
end

-- Tool: read_resource
function M.read_resource(db, params)
    local workspace_id = params.workspace_id
    local path = params.path
    if not workspace_id or not path then return nil, "workspace_id and path required" end

    local stmt = db:prepare([[
        SELECT d.id, d.file_path, v.content, v.version_number, v.created_at
        FROM documents d
        JOIN document_versions v ON d.current_version_id = v.id
        WHERE d.workspace_id = ? AND d.file_path = ?
    ]])
    stmt:bind_values(workspace_id, path)

    if stmt:step() == sqlite3.ROW then
        local row = stmt:get_named_values()
        stmt:finalize()
        return {
            path = row.file_path,
            content = row.content,
            version = row.version_number,
            updated_at = row.created_at
        }
    end
    stmt:finalize()
    return nil, "File not found"
end

-- Tool: propose_change (SAFE - creates conflict, doesn't overwrite)
function M.propose_change(db, params)
    local workspace_id = params.workspace_id
    local path = params.path
    local content = params.content
    local reason = params.reason or "AI proposal"
    local proposer = params.proposer or "claude"

    if not workspace_id or not path or not content then
        return nil, "workspace_id, path, and content required"
    end

    -- Find document
    local stmt = db:prepare([[
        SELECT d.id, d.current_version_id, v.content as current_content
        FROM documents d
        LEFT JOIN document_versions v ON d.current_version_id = v.id
        WHERE d.workspace_id = ? AND d.file_path = ?
    ]])
    stmt:bind_values(workspace_id, path)

    local doc = nil
    if stmt:step() == sqlite3.ROW then
        doc = stmt:get_named_values()
    end
    stmt:finalize()

    if not doc then return nil, "Document not found" end

    -- Create proposal as conflict (user must approve)
    local conflict_id = db_mod.uuid()
    stmt = db:prepare([[
        INSERT INTO conflict_versions
        (id, document_id, user_content, ai_content, ancestor_version_id, proposer, proposal_reason)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]])
    stmt:bind_values(
        conflict_id,
        doc.id,
        doc.current_content or "",
        content,
        doc.current_version_id,
        proposer,
        reason
    )
    stmt:step()
    stmt:finalize()

    -- Notify UI
    websocket_mod.broadcast({
        type = "proposal",
        conflict_id = conflict_id,
        document_id = doc.id,
        file_path = path,
        reason = reason
    })

    return {
        status = "proposed",
        conflict_id = conflict_id,
        message = "Change proposed. User must review and approve."
    }
end

-- Tool definitions for tools/list
local TOOLS = {
    {
        name = "list_files",
        description = "List all files in a workspace",
        inputSchema = {
            type = "object",
            properties = {
                workspace_id = { type = "string", description = "Workspace UUID" }
            },
            required = { "workspace_id" }
        }
    },
    {
        name = "read_resource",
        description = "Read the content of a file",
        inputSchema = {
            type = "object",
            properties = {
                workspace_id = { type = "string" },
                path = { type = "string", description = "File path within workspace" }
            },
            required = { "workspace_id", "path" }
        }
    },
    {
        name = "propose_change",
        description = "Propose a change to a file. User must approve before it takes effect.",
        inputSchema = {
            type = "object",
            properties = {
                workspace_id = { type = "string" },
                path = { type = "string" },
                content = { type = "string", description = "Proposed new content" },
                reason = { type = "string", description = "Explanation for the change" }
            },
            required = { "workspace_id", "path", "content" }
        }
    }
}

local tool_handlers = {
    list_files = M.list_files,
    read_resource = M.read_resource,
    propose_change = M.propose_change
}

-- JSON-RPC Dispatcher
function M.handle_request(db, request)
    if not request or request.jsonrpc ~= "2.0" then
        return rpc_error(nil, ERR_INVALID_REQUEST, "Invalid JSON-RPC 2.0 request")
    end

    local id = request.id
    local method = request.method
    local params = request.params or {}

    -- Initialize
    if method == "initialize" then
        return rpc_result(id, {
            protocolVersion = "2024-11-05",
            serverInfo = { name = "connect", version = "2.0.0" },
            capabilities = {
                tools = { listChanged = false },
                resources = { subscribe = false, listChanged = false }
            }
        })
    end

    -- List tools
    if method == "tools/list" then
        return rpc_result(id, { tools = TOOLS })
    end

    -- Call tool
    if method == "tools/call" then
        local tool_name = params.name
        local tool_args = params.arguments or {}

        local handler = tool_handlers[tool_name]
        if not handler then
            return rpc_error(id, ERR_METHOD_NOT_FOUND, "Unknown tool: " .. tostring(tool_name))
        end

        local result, err = handler(db, tool_args)
        if err then
            return rpc_error(id, ERR_INTERNAL, err)
        end

        return rpc_result(id, {
            content = {{ type = "text", text = EncodeJson(result) }}
        })
    end

    -- Notifications (no response needed)
    if method == "notifications/initialized" then
        return nil
    end

    return rpc_error(id, ERR_METHOD_NOT_FOUND, "Method not found: " .. tostring(method))
end

-- WebSocket Handler
function M.handle_websocket(db, ws)
    ws:write(EncodeJson({ jsonrpc = "2.0", method = "notifications/initialized" }))

    while true do
        local data, op = ws:read()
        if not data then break end

        local ok, request = pcall(DecodeJson, data)
        if not ok then
            ws:write(EncodeJson(rpc_error(nil, ERR_PARSE, "Parse error")))
        else
            local response = M.handle_request(db, request)
            if response then
                ws:write(EncodeJson(response))
            end
        end
    end
end

return M
