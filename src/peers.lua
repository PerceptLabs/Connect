local sqlite3 = require("lsqlite3")
local db_utils = require("src.db")
local security = require("src.security")
local M = {}

function M.list(db)
    local peers = {}
    local stmt = db:prepare("SELECT * FROM peers WHERE is_active = 1 ORDER BY created_at DESC")
    for row in stmt:nrows() do
        -- Decrypt API key for use
        if row.api_key and row.api_key ~= "" then
            row.api_key = security.decrypt(row.api_key)
        end
        table.insert(peers, row)
    end
    stmt:finalize()
    return peers
end

function M.create(db, peer)
    local id = peer.id or db_utils.uuid()

    -- Encrypt API key
    local encrypted_key = ""
    if peer.api_key and peer.api_key ~= "" then
        encrypted_key = security.encrypt(peer.api_key)
    end

    local stmt = db:prepare([[
        INSERT OR REPLACE INTO peers (id, name, provider, base_url, api_key, model_id, context_window)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]])
    stmt:bind_values(
        id,
        peer.name,
        peer.provider,
        peer.base_url,
        encrypted_key,
        peer.model_id,
        peer.context_window or 4096
    )
    if stmt:step() ~= sqlite3.DONE then
        return nil, "Failed to create/update peer"
    end
    stmt:finalize()
    return { id = id }
end

function M.delete(db, id)
    local stmt = db:prepare("DELETE FROM peers WHERE id = ?")
    stmt:bind_values(id)
    stmt:step()
    stmt:finalize()
    return true
end

return M
