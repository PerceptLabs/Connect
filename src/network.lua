local M = {}

function M.get_lan_ip()
    -- Try getting IP via hostname -I (common on Linux)
    local f = io.popen("hostname -I")
    if f then
        local content = f:read("*a")
        f:close()
        local ip = content:match("(%d+%.%d+%.%d+%.%d+)")
        if ip then return ip end
    end

    -- Fallback to ifconfig
    f = io.popen("ifconfig")
    if f then
        local content = f:read("*a")
        f:close()
        -- Look for inet addr:192... or inet 192... avoiding 127.0.0.1
        for ip in content:gmatch("inet %a*:?%s*(%d+%.%d+%.%d+%.%d+)") do
            if ip ~= "127.0.0.1" then return ip end
        end
    end

    return "127.0.0.1"
end

return M
