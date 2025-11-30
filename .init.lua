package.path = "/zip/?.lua;" .. package.path
local sqlite3 = require("lsqlite3")
local db_mod = require("src.db")
local llm_mod = require("src.llm")
local docs_mod = require("src.docs")
local context_mod = require("src.context")
local sync_mod = require("src.sync")
local peers_mod = require("src.peers")
local discovery_mod = require("src.discovery")
local security = require("src.security")

-- Initialize Database
local db = db_mod.init()
db_mod.migrate(db)

-- Safeguard 1: FTS5 Capability Check
local fts_available = false
local fts_status, fts_err = pcall(function()
    local res = db:exec("CREATE VIRTUAL TABLE IF NOT EXISTS fts_test_check USING fts5(content)")
    if res == sqlite3.OK then
        fts_available = true
        db:exec("DROP TABLE fts_test_check")
    else
        error("FTS5 init failed code " .. res)
    end
end)
if not fts_available then
    print("WARNING: Standard Redbean Detected. FTS5 missing. Falling back to Shim logic. (" .. tostring(fts_err) .. ")")
else
    print("SUCCESS: Purpose-Built Redbean Detected. FTS5 Enabled.")
end

-- Migration: peers.json -> SQLite
local function migrate_peers()
    local f = io.open("peers.json", "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, data = pcall(DecodeJson, content)
        if ok and data.peers then
            for _, p in ipairs(data.peers) do
                -- Map old fields to new schema
                local new_peer = {
                    id = p.id,
                    name = p.name,
                    provider = p.provider,
                    base_url = p.api_url or (p.provider == "ollama" and "http://localhost:11434" or "https://api.openai.com"),
                    api_key = p.api_key_env and (os.getenv(p.api_key_env) or "") or "",
                    model_id = p.model,
                    context_window = 4096
                }
                peers_mod.create(db, new_peer)
            end
            os.rename("peers.json", "peers.json.bak")
            print("Migrated peers.json to database.")
        end
    end
end
migrate_peers()

-- Helpers
local function json_response(data, status)
    status = status or 200
    SetStatus(status)
    SetHeader("Content-Type", "application/json")
    Write(EncodeJson(data))
end

local function get_json_body()
    local body = GetBody()
    if not body or body == "" then return nil end
    local ok, data = pcall(DecodeJson, body)
    if ok then return data else return nil end
end

function OnHttpRequest()
    local path = GetPath()
    local method = GetMethod()

    -- CORS
    SetHeader("Access-Control-Allow-Origin", "*")
    SetHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS, DELETE")
    SetHeader("Access-Control-Allow-Headers", "Content-Type")

    if method == "OPTIONS" then
        SetStatus(200)
        return
    end

    -- Router
    if path == "/api/workspaces" then
        if method == "GET" then
            local items = {}
            local stmt = db:prepare("SELECT * FROM workspaces ORDER BY created_at DESC")
            for row in stmt:nrows() do table.insert(items, row) end
            stmt:finalize()
            json_response({ workspaces = items })
        elseif method == "POST" then
            local data = get_json_body()
            if not data or not data.name then
                json_response({ error = "Missing name" }, 400)
                return
            end
            local id = db_mod.uuid()
            local slug = data.name:lower():gsub("%s+", "-")
            local stmt = db:prepare("INSERT INTO workspaces (id, name, slug) VALUES (?, ?, ?)")
            stmt:bind_values(id, data.name, slug)
            stmt:step()
            stmt:finalize()
            json_response({ id = id, name = data.name, slug = slug })
        end

    elseif path:match("^/api/workspaces/([^/]+)/threads$") and method == "GET" then
        local ws_id = path:match("^/api/workspaces/([^/]+)/threads$")
        local items = {}
        local stmt = db:prepare("SELECT * FROM threads WHERE workspace_id = ? ORDER BY updated_at DESC")
        stmt:bind_values(ws_id)
        for row in stmt:nrows() do table.insert(items, row) end
        stmt:finalize()
        json_response({ threads = items })

    elseif path == "/api/threads" and method == "POST" then
        local data = get_json_body()
        if not data or not data.workspace_id or not data.name then
            json_response({ error = "Missing params" }, 400)
            return
        end
        local id = db_mod.uuid()
        local stmt = db:prepare("INSERT INTO threads (id, workspace_id, name) VALUES (?, ?, ?)")
        stmt:bind_values(id, data.workspace_id, data.name)
        stmt:step()
        stmt:finalize()
        json_response({ id = id, name = data.name, workspace_id = data.workspace_id })

    -- Peer Management
    elseif path == "/api/peers" then
        if method == "GET" then
            local peers = peers_mod.list(db)
            json_response(peers)
        elseif method == "POST" then
            local data = get_json_body()
            if not data then json_response({ error = "Body required" }, 400) return end
            local res, err = peers_mod.create(db, data)
            if not res then json_response({ error = err }, 500) else json_response(res) end
        end

    elseif path:match("^/api/peers/(.+)$") and method == "DELETE" then
        local id = path:match("^/api/peers/(.+)$")
        peers_mod.delete(db, id)
        json_response({ success = true })

    elseif path == "/api/peers/discover" and method == "POST" then
        local data = get_json_body()
        if not data or not data.provider or not data.base_url then
            json_response({ error = "Missing provider/base_url" }, 400)
            return
        end
        local res = discovery_mod.discover(data.provider, data.base_url, data.api_key)
        json_response(res)

    elseif path == "/api/docs/commit" and method == "POST" then
        local data = get_json_body()
        if not data or not data.workspace_id or not data.file_path or not data.content then
            json_response({ error = "Missing parameters" }, 400)
            return
        end
        local result = docs_mod.commit(
            db,
            data.workspace_id,
            data.file_path,
            data.content,
            data.message or "Update",
            data.author_type or "user",
            data.author_id or "user"
        )
        json_response(result)

    elseif path == "/api/context/select" and method == "POST" then
        local data = get_json_body()
        if not data or not data.thread_id then
            json_response({ error = "Missing thread_id" }, 400)
            return
        end
        local chunks = context_mod.select(
            db,
            data.thread_id,
            data.query,
            data.max_tokens or 4000
        )
        json_response({ chunks = chunks })

    elseif path == "/api/context/estimate" and method == "POST" then
        local data = get_json_body()
        if not data or not data.thread_id then
            json_response({ error = "Missing thread_id" }, 400)
            return
        end
        local estimate = context_mod.estimate(
            db,
            data.thread_id,
            data.query,
            data.max_tokens or 4096
        )
        json_response(estimate)

    elseif path == "/api/llm/generate" and method == "POST" then
        local data = get_json_body()
        if not data or not data.peer_id or not data.messages then
            json_response({ error = "Missing parameters" }, 400)
            return
        end

        -- Load Peer from DB
        local stmt = db:prepare("SELECT * FROM peers WHERE id = ?")
        stmt:bind_values(data.peer_id)
        local has_row = stmt:step()
        if has_row ~= sqlite3.ROW then
            stmt:finalize()
            json_response({ error = "Peer not found" }, 404)
            return
        end

        -- Construct peer object
        local peer = {}
        -- Map columns to table
        -- lsqlite3 row access by name depends on how we iterate or use row_values
        -- step() doesn't return table. get_named_values() does.
        peer = stmt:get_named_values()
        if peer.api_key and peer.api_key ~= "" then
            peer.api_key = security.decrypt(peer.api_key)
        end
        stmt:finalize()

        local result = llm_mod.generate(peer, data.messages, data.context_chunks or {})
        json_response(result)

    elseif path == "/api/sync/status" and method == "POST" then
        local result = sync_mod.check_sync(db)
        json_response(result)

    elseif path == "/api/pin" and method == "POST" then
        local data = get_json_body()
        local stmt = db:prepare("INSERT OR IGNORE INTO pinned_documents (workspace_id, document_id) VALUES (?, ?)")
        stmt:bind_values(data.workspace_id, data.document_id)
        stmt:step()
        stmt:finalize()
        json_response({ success = true })

    elseif path == "/api/unpin" and method == "DELETE" then
        local data = get_json_body()
        local stmt = db:prepare("DELETE FROM pinned_documents WHERE workspace_id = ? AND document_id = ?")
        stmt:bind_values(data.workspace_id, data.document_id)
        stmt:step()
        stmt:finalize()
        json_response({ success = true })

    elseif path == "/api/pins" and method == "GET" then
        local params = GetParams()
        local ws_id = ""
        for _, p in ipairs(params) do
            if p[1] == "workspace_id" then ws_id = p[2] end
        end
        local items = {}
        if ws_id ~= "" then
            local stmt = db:prepare("SELECT document_id FROM pinned_documents WHERE workspace_id = ?")
            stmt:bind_values(ws_id)
            for row in stmt:nrows() do table.insert(items, row.document_id) end
            stmt:finalize()
        end
        json_response({ pins = items })

    else
        if not ServeAsset(path) then
             ServeAsset("/index.html")
        end
    end
end
