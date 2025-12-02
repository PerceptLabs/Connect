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
local network = require("src.network")
local auth = require("src.auth")
local merge_mod = require("src.merge")
local search_mod = require("src.search")
local backup_mod = require("src.backup")
local websocket_mod = require("src.websocket")
local mcp_mod = require("src.mcp")
local memory_mod = require("src.memory")

-- Network Configuration
local HOST = os.getenv("CONNECT_HOST") or "127.0.0.1"
local PORT = os.getenv("CONNECT_PORT") or "8080"
-- Note: Redbean 2.x handles listening address via ProgramArguments or hardcoded.
-- But since we are inside the Lua script, we can't change the bind address easily if it's already started.
-- However, Redbean usually defaults to 127.0.0.1:8080 unless args are passed.
-- If this script is the entry point, we can assume the environment is set up.
-- We can print the info though.

if HOST == "0.0.0.0" then
    print("WARNING: Network access enabled on 0.0.0.0")
end

-- Initialize Database
local db = db_mod.init()
db_mod.migrate(db)

-- Auth Bootstrap
auth.bootstrap(db)

-- Safeguard 1: FTS5 Capability Check
-- Safeguard 1: FTS5 Capability Check & Schema Init
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

if fts_available then
    print("SUCCESS: Purpose-Built Redbean Detected. FTS5 Enabled.")
    db:exec([[
        CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(
            content,
            label,
            document_version_id UNINDEXED,
            token_count UNINDEXED
        );
    ]])
else
    print("WARNING: Standard Redbean Detected. FTS5 missing. Falling back to Shim logic. (" .. tostring(fts_err) .. ")")
    db:exec([[
        CREATE TABLE IF NOT EXISTS chunk_fts (
            rowid INTEGER PRIMARY KEY,
            content TEXT,
            label TEXT,
            document_version_id TEXT,
            token_count INTEGER
        );
    ]])
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

    -- Authentication Middleware
    if path:match("^/api/") then
        local client_ip = GetRemoteAddr()
        local is_localhost = (client_ip == "127.0.0.1" or client_ip == "::1")

        -- Public Endpoints (Login/Recovery)
        if path:match("^/api/auth/") then
            -- Pass through

        -- MCP: Always requires API Token
        elseif path:match("^/api/mcp") then
            local auth_header = GetHeader("Authorization")
            if not auth.verify_api_token(db, auth_header) then
                json_response({ error = "Unauthorized: Invalid API Token" }, 401)
                return
            end

            -- Handle MCP WebSocket
            if IsWebSocket() then
                local ws = UpgradeToWebSocket()
                mcp_mod.handle_websocket(db, ws)
                return
            else
                json_response({ error = "MCP requires WebSocket connection" }, 400)
                return
            end

        -- Regular API
        else
            -- Check User Count for Localhost Logic
            -- Cache this? For now, query.
            local user_count = 1
            local count_stmt = db:prepare("SELECT count(*) FROM users")
            if count_stmt:step() == sqlite3.ROW then user_count = count_stmt:get_value(0) end
            count_stmt:finalize()

            local auth_required = true
            if is_localhost and user_count <= 1 then
                auth_required = false
            end

            if auth_required then
                local auth_header = GetHeader("Authorization")

                -- Check query param for WebSocket
                if not auth_header and path == "/api/ws" then
                    local params = GetParams()
                    for _, p in ipairs(params) do
                        if p[1] == "token" then
                            auth_header = "Bearer " .. p[2]
                        end
                    end
                end

                if not auth.verify_session(auth_header) then
                    json_response({ error = "Unauthorized" }, 401)
                    return
                end
            end
        end
    end

    -- Router
    -- Auth Routes
    if path == "/api/auth/login" and method == "POST" then
        local data = get_json_body()
        if not data then json_response({error="Missing body"}, 400) return end

        local token
        if data.password then
            token = auth.login(db, data.password)
        elseif data.recovery_token then
            token = auth.login_recovery(db, data.recovery_token)
        end

        if token then
            json_response({ token = token })
        else
            json_response({ error = "Invalid credentials" }, 401)
        end
        return -- Stop processing

    elseif path == "/api/auth/reset-password" and method == "POST" then
        local data = get_json_body()
        if not data or not data.recovery_token or not data.new_password then
            json_response({ error = "Missing params" }, 400)
            return
        end
        if auth.reset_password(db, data.recovery_token, data.new_password) then
             json_response({ success = true })
        else
             json_response({ error = "Invalid recovery token" }, 401)
        end
        return

    elseif path == "/api/auth/request-recovery" and method == "POST" then
        -- Optional: restrict to localhost? "Physical access" implies local net or machine.
        -- Let's restrict to localhost for safety, as per description "Physical access recovery".
        -- The user said "From phone: tap Forgot Password". Phone is remote.
        -- So we must allow from remote.
        auth.request_recovery(db)
        json_response({ success = true }) -- Always say success to prevent enumeration?
        return

    elseif path == "/api/tokens" and method == "POST" then
        -- Generate API token (Authenticated User only)
        -- Middleware handled auth check (if remote/multi-user).
        local data = get_json_body()
        local name = (data and data.name) or "Unnamed Token"
        local token = auth.create_api_token(db, name)
        json_response({ token = token })
        return

    elseif path == "/api/network/info" and method == "GET" then
        local ip = network.get_lan_ip()
        json_response({
            url = "http://" .. ip .. ":" .. PORT,
            host = HOST,
            port = PORT,
            ip = ip
        })

    elseif path == "/api/security/warning" and method == "GET" then
        json_response({
            warning = (HOST ~= "127.0.0.1" and HOST ~= "localhost") and "Network access enabled. Ensure trusted network." or nil,
            encrypted = true -- XOR is used
        })

    elseif path == "/api/workspaces" then
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

    elseif path:match("^/api/threads/([^/]+)/messages$") then
        local thread_id = path:match("^/api/threads/([^/]+)/messages$")

        if method == "GET" then
            local items = {}
            local stmt = db:prepare("SELECT * FROM messages WHERE thread_id = ? ORDER BY created_at ASC")
            stmt:bind_values(thread_id)
            for row in stmt:nrows() do table.insert(items, row) end
            stmt:finalize()
            json_response({ messages = items })

        elseif method == "POST" then
            local data = get_json_body()
            if not data or not data.content or not data.role then
                json_response({ error = "Missing content/role" }, 400)
                return
            end
            local id = db_mod.uuid()
            local stmt = db:prepare("INSERT INTO messages (id, thread_id, role, content, metadata) VALUES (?, ?, ?, ?, ?)")
            local metadata = data.metadata and EncodeJson(data.metadata) or nil
            stmt:bind_values(id, thread_id, data.role, data.content, metadata)
            stmt:step()
            stmt:finalize()

        -- Fix 8.4: Update thread updated_at
        local up = db:prepare("UPDATE threads SET updated_at = CURRENT_TIMESTAMP WHERE id = ?")
        up:bind_values(thread_id)
        up:step()
        up:finalize()

            json_response({ id = id, thread_id = thread_id, role = data.role, content = data.content, created_at = os.date("!%Y-%m-%dT%H:%M:%S") })
        end

    elseif path:match("^/api/workspaces/(.+)$") and method == "DELETE" then
        -- Fix 8.12: Delete Workspace
        local id = path:match("^/api/workspaces/(.+)$")
        -- Cascade delete is handled by DB schema ON DELETE CASCADE
        local stmt = db:prepare("DELETE FROM workspaces WHERE id = ?")
        stmt:bind_values(id)
        stmt:step()
        stmt:finalize()
        json_response({ success = true })

    elseif path:match("^/api/threads/(.+)$") and method == "DELETE" then
        -- Fix 8.12: Delete Thread
        local id = path:match("^/api/threads/(.+)$")
        local stmt = db:prepare("DELETE FROM threads WHERE id = ?")
        stmt:bind_values(id)
        stmt:step()
        stmt:finalize()
        json_response({ success = true })

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

    elseif path:match("^/api/peers/(.+)$") and method == "PUT" then
        -- Fix 8.13: Update Peer
        local id = path:match("^/api/peers/(.+)$")
        local data = get_json_body()
        if not data then json_response({ error = "Missing body" }, 400) return end

        -- Logic to update (peers.lua usually has create/list/delete, need update)
        -- We can just run SQL here or add to peers module. Let's add here for speed.
        -- Updateable fields: name, base_url, api_key, model_id, context_window, is_active
        local sql = "UPDATE peers SET "
        local params = {}
        local fields = {}

        if data.name then table.insert(fields, "name = ?"); table.insert(params, data.name) end
        if data.base_url then table.insert(fields, "base_url = ?"); table.insert(params, data.base_url) end
        if data.api_key then
            -- Encrypt
            local enc = security.encrypt(data.api_key)
            table.insert(fields, "api_key = ?"); table.insert(params, enc)
        end
        if data.model_id then table.insert(fields, "model_id = ?"); table.insert(params, data.model_id) end
        if data.context_window then table.insert(fields, "context_window = ?"); table.insert(params, data.context_window) end
        if data.is_active ~= nil then table.insert(fields, "is_active = ?"); table.insert(params, data.is_active) end

        if #fields == 0 then json_response({ success = true }) return end -- No op

        sql = sql .. table.concat(fields, ", ") .. " WHERE id = ?"
        table.insert(params, id)

        local stmt = db:prepare(sql)
        stmt:bind_values(table.unpack(params))
        stmt:step()
        stmt:finalize()

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

    elseif path == "/api/conflicts/resolve" and method == "POST" then
        local data = get_json_body()
        if not data or not data.workspace_id or not data.file_path or not data.content then
            json_response({ error = "Missing resolve params" }, 400)
            return
        end

        local res = docs_mod.commit(
            db,
            data.workspace_id,
            data.file_path,
            data.content,
            "Conflict Resolved",
            "user",
            "user"
        )

        -- Cleanup conflict
        local doc_id = res.document_id
        if doc_id then
             local stmt = db:prepare("DELETE FROM conflict_versions WHERE document_id = ?")
             stmt:bind_values(doc_id)
             stmt:step()
             stmt:finalize()
        end
        json_response(res)

    elseif path:match("^/api/conflicts/(.+)/ancestor$") and method == "GET" then
        local conflict_id = path:match("^/api/conflicts/(.+)/ancestor$")
        -- Get ancestor version ID from conflict
        local stmt = db:prepare("SELECT ancestor_version_id FROM conflict_versions WHERE id = ?")
        stmt:bind_values(conflict_id)
        if stmt:step() == sqlite3.ROW then
            local ver_id = stmt:get_value(0)
            stmt:finalize()

            -- Fetch content
            local v_stmt = db:prepare("SELECT content, version_number FROM document_versions WHERE id = ?")
            v_stmt:bind_values(ver_id)
            if v_stmt:step() == sqlite3.ROW then
                local content = v_stmt:get_value(0)
                local ver_num = v_stmt:get_value(1)
                v_stmt:finalize()
                json_response({ content = content, version_number = ver_num })
            else
                v_stmt:finalize()
                json_response({ error = "Ancestor version not found" }, 404)
            end
        else
            stmt:finalize()
            json_response({ error = "Conflict not found" }, 404)
        end

    elseif path:match("^/api/conflicts/(.+)/automerge$") and method == "POST" then
        local conflict_id = path:match("^/api/conflicts/(.+)/automerge$")

        -- Fetch conflict details
        local stmt = db:prepare([[
            SELECT c.user_content, c.ai_content, v.content as base_content
            FROM conflict_versions c
            JOIN document_versions v ON c.ancestor_version_id = v.id
            WHERE c.id = ?
        ]])
        stmt:bind_values(conflict_id)
        if stmt:step() == sqlite3.ROW then
            local local_text = stmt:get_value(0)
            local remote_text = stmt:get_value(1)
            local base_text = stmt:get_value(2)
            stmt:finalize()

            local merged = merge_mod.diff3_merge(local_text, base_text, remote_text)
            json_response(merged)
        else
            stmt:finalize()
            json_response({ error = "Conflict or base version not found" }, 404)
        end

    elseif path == "/api/conflicts" and method == "GET" then
        -- List active conflicts
        -- Join conflict_versions with documents
        local items = {}
        local stmt = db:prepare([[
            SELECT cv.*, d.workspace_id, d.file_path
            FROM conflict_versions cv
            JOIN documents d ON cv.document_id = d.id
        ]])
        for row in stmt:nrows() do
            table.insert(items, row)
        end
        stmt:finalize()
        json_response({ conflicts = items })

    elseif path == "/api/search" and method == "GET" then
        local params = GetParams()
        local query = ""
        for _, p in ipairs(params) do
            if p[1] == "query" then query = p[2] end
        end

        if query == "" then
            json_response({ results = {} })
        else
            -- Check for filters in query string if needed, but parser handles it from main query string usually.
            -- Or we can pass filters as separate params.
            -- The plan says "Parse query syntax server-side".
            local results = search_mod.search(db, query)
            json_response({ results = results })
        end

    elseif path == "/api/backup/export" and method == "GET" then
        local params = GetParams()
        local ws_id = ""
        for _, p in ipairs(params) do
            if p[1] == "workspace_id" then ws_id = p[2] end
        end
        if ws_id == "" then
            json_response({ error = "Missing workspace_id" }, 400)
            return
        end

        local data, err = backup_mod.export_workspace(db, ws_id)
        if not data then
            json_response({ error = err }, 404)
        else
            SetStatus(200)
            SetHeader("Content-Type", "application/json")
            SetHeader("Content-Disposition", "attachment; filename=workspace_" .. ws_id .. ".json")
            Write(EncodeJson(data))
        end

    elseif path == "/api/backup/import" and method == "POST" then
        local data = get_json_body()
        if not data then
            json_response({ error = "Invalid JSON" }, 400)
            return
        end

        local ok, err = backup_mod.import_workspace(db, data)
        if ok then
            json_response({ success = true })
        else
            json_response({ error = err }, 500)
        end

    elseif path == "/api/memories" and method == "GET" then
        local params = GetParams()
        local ws_id = ""
        for _, p in ipairs(params) do
            if p[1] == "workspace_id" then ws_id = p[2] end
        end
        if ws_id == "" then
            json_response({ error = "workspace_id required" }, 400)
            return
        end
        json_response({ memories = memory_mod.list(db, ws_id) })

    elseif path == "/api/memories/summarize" and method == "POST" then
        local data = get_json_body()
        if not data or not data.thread_id then
            json_response({ error = "thread_id required" }, 400)
            return
        end

        -- Get active peer
        local peer = nil
        local stmt = db:prepare("SELECT * FROM peers WHERE is_active = 1 LIMIT 1")
        if stmt:step() == sqlite3.ROW then
            peer = stmt:get_named_values()
            if peer.api_key and peer.api_key ~= "" then
                peer.api_key = security.decrypt(peer.api_key)
            end
        end
        stmt:finalize()

        if not peer then
            json_response({ error = "No active peer" }, 400)
            return
        end

        local result, err = memory_mod.summarize_thread(db, data.thread_id, peer)
        if result then
            json_response(result)
        else
            json_response({ error = err }, 500)
        end

    elseif path:match("^/api/memories/(.+)$") and method == "DELETE" then
        local memory_id = path:match("^/api/memories/(.+)$")
        memory_mod.delete(db, memory_id)
        json_response({ success = true })

    elseif path == "/api/ws" then
        if IsWebSocket() then
            local ws = UpgradeToWebSocket()
            websocket_mod.handle(nil, ws)
            return
        else
            SetStatus(400)
            Write("Not a WebSocket request")
        end

    else
        if not ServeAsset(path) then
             ServeAsset("/index.html")
        end
    end
end
