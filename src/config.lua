local M = {}

function M.load_peers()
    local file = io.open("peers.json", "r")
    if not file then
        return { peers = {} }
    end
    local content = file:read("*a")
    file:close()

    local ok, data = pcall(DecodeJson, content)
    if not ok then
        -- Fallback if DecodeJson is not global (standard redbean has it)
        -- or if JSON is invalid
        print("Error parsing peers.json: " .. tostring(data))
        return { peers = {} }
    end

    return data
end

return M
