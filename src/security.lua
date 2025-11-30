local M = {}
-- Simple XOR key (Obfuscation only, not production crypto)
local KEY = "connect-local-key"

function M.encrypt(text)
    if not text or text == "" then return "" end
    local res = {}
    for i = 1, #text do
        local key_char = string.byte(KEY, (i - 1) % #KEY + 1)
        -- XOR and convert to hex
        table.insert(res, string.format("%02x", string.byte(text, i) ~ key_char))
    end
    return table.concat(res)
end

function M.decrypt(hex)
    if not hex or hex == "" then return "" end
    local res = {}
    for i = 1, #hex, 2 do
        local byte_str = hex:sub(i, i+1)
        local byte = tonumber(byte_str, 16)
        if not byte then return "" end
        local key_idx = math.floor((i - 1) / 2)
        local key_char = string.byte(KEY, key_idx % #KEY + 1)
        table.insert(res, string.char(byte ~ key_char))
    end
    return table.concat(res)
end

return M
