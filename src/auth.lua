local M = {}

local token = os.getenv("CONNECT_TOKEN")

if not token then
    -- Generate random token
    local f = io.open("/dev/urandom", "rb")
    if f then
        local bytes = f:read(16)
        f:close()
        token = ""
        for i=1, #bytes do
            token = token .. string.format("%02x", string.byte(bytes, i))
        end
        print("SECURITY WARNING: No CONNECT_TOKEN set.")
        print("Generated temporary token: " .. token)
    else
        token = "connect-default"
        print("WARNING: Could not generate random token. Using default.")
    end
end

function M.check(req_token, client_ip)
    -- Bypass for localhost
    if client_ip == "127.0.0.1" or client_ip == "::1" then
        return true
    end

    if req_token == "Bearer " .. token then
        return true
    end

    return false
end

function M.get_token()
    return token
end

return M
