local sqlite3 = require("lsqlite3")

local M = {}
local DB_PATH = "connect.db"

function M.init()
    local db = sqlite3.open(DB_PATH)
    if not db then
        error("Failed to open database: " .. DB_PATH)
    end

    -- Enable WAL mode for concurrency
    db:exec("PRAGMA journal_mode=WAL;")

    -- Foreign keys are off by default in SQLite
    db:exec("PRAGMA foreign_keys = ON;")

    return db
end

function M.migrate(db)
    local file = io.open("schema.sql", "r")
    if not file then
        error("Could not find schema.sql")
    end
    local schema_sql = file:read("*a")
    file:close()

    local result = db:exec(schema_sql)
    if result ~= sqlite3.OK then
        error("Migration failed: " .. db:errmsg())
    end
end

-- Helper to generate UUID v4
function M.uuid()
    -- Try /dev/urandom for true randomness
    local f = io.open("/dev/urandom", "rb")
    local bytes
    if f then
        bytes = f:read(16)
        f:close()
    else
        -- Fallback (unsafe but unlikely in this env)
        bytes = ""
        for i=1,16 do bytes = bytes .. string.char(math.random(0, 255)) end
    end

    local b = {string.byte(bytes, 1, 16)}

    -- Set version 4 (0100xxxx) -> b[7]
    b[7] = (b[7] & 0x0f) | 0x40

    -- Set variant 10xxxxxx -> b[9]
    b[9] = (b[9] & 0x3f) | 0x80

    return string.format("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        b[1], b[2], b[3], b[4],
        b[5], b[6],
        b[7], b[8],
        b[9], b[10],
        b[11], b[12], b[13], b[14], b[15], b[16]
    )
end

return M
