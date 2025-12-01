local M = {}

local clients = {}

function M.handle(req, ws)
    -- Add to clients list
    -- We use the ws object as key
    local id = tostring(ws)
    clients[ws] = { id = id, last_seen = os.time() }

    -- Send initial "hello"
    ws:write(EncodeJson({ type = "connected", id = id }))

    while true do
        local data, op = ws:read()
        if not data then break end -- Closed

        -- Handle keepalive or messages
        -- If op is ping? Redbean handles ping/pong usually at protocol level.
        -- We can just update last_seen.
        if clients[ws] then
            clients[ws].last_seen = os.time()
        end

        -- Echo back or handle commands?
        -- For now, we only broadcast FROM server to clients.
        -- Clients might send "typing" status?
        -- If data is JSON, parse it.
        local ok, msg = pcall(DecodeJson, data)
        if ok and msg then
             if msg.type == "ping" then
                 ws:write(EncodeJson({ type = "pong" }))
             end
        end
    end

    clients[ws] = nil
end

function M.broadcast(message)
    -- Message should be a table
    local payload = EncodeJson(message)
    for ws, _ in pairs(clients) do
        pcall(function()
            ws:write(payload)
        end)
    end
end

return M
