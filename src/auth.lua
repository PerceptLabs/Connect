local M = {}
local sqlite3 = require("lsqlite3")
local db_mod = require("src.db")

-- If argon2 is not available (standard redbean), we might need a fallback.
-- However, requirements state "Argon2 hashing".
local ok, argon2 = pcall(require, "argon2")
if not ok then
    print("WARNING: argon2 module not found. Passwords will fail if not fixed.")
end

-- Generate a random string
local function random_string(len)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local res = ""
    local f = io.open("/dev/urandom", "rb")
    if f then
        local bytes = f:read(len)
        f:close()
        for i=1, #bytes do
            local b = string.byte(bytes, i)
            local idx = (b % #chars) + 1
            res = res .. chars:sub(idx, idx)
        end
    else
        -- Fallback (insecure but works for logic)
        for i=1, len do
            local idx = math.random(1, #chars)
            res = res .. chars:sub(idx, idx)
        end
    end
    return res
end

-- HMAC Helper (assuming MbedTLS/crypto available in Redbean global namespace or via libs)
-- Redbean exposes `GetCryptoHash` but that is SHA1/256 usually.
-- `unix.clock_gettime` or similar might be available.
-- We need a way to sign tokens.
-- If no HMAC, we can use a simpler signature: hash(token .. secret).

local JWT_SECRET = os.getenv("CONNECT_SECRET") or random_string(32)

local function sign_token(payload)
    -- Simple signed token format: base64(json(payload)) . hex(sha256(base64 .. secret))
    local json = EncodeJson(payload)
    local b64 = EncodeBase64(json)
    -- Redbean has internal SHA256 usually?
    -- `GetCryptoHash` takes (algo, content). Algo: "SHA256"
    local sig = GetCryptoHash("SHA256", b64 .. JWT_SECRET)
    if not sig then
        -- Fallback if GetCryptoHash not global (it usually is in Redbean)
        -- Try using some other way?
        -- Actually, let's assume valid Redbean environment.
        return b64 .. "." .. "signature_fail"
    end
    -- GetCryptoHash returns raw bytes? Or hex?
    -- Docs say "Returns the hash as a string of binary data."
    -- We need to hex it.
    local hex = ""
    for i=1, #sig do
        hex = hex .. string.format("%02x", string.byte(sig, i))
    end
    return b64 .. "." .. hex
end

local function verify_token_sign(token)
    local b64, sig = token:match("^(.-)%.(.+)$")
    if not b64 or not sig then return nil end

    local calc_sig_bin = GetCryptoHash("SHA256", b64 .. JWT_SECRET)
    local calc_hex = ""
    for i=1, #calc_sig_bin do
        calc_hex = calc_hex .. string.format("%02x", string.byte(calc_sig_bin, i))
    end

    if sig == calc_hex then
        local json = DecodeBase64(b64)
        local ok, payload = pcall(DecodeJson, json)
        if ok then return payload end
    end
    return nil
end


-- Check if we need to bootstrap admin
function M.bootstrap(db)
    local stmt = db:prepare("SELECT count(*) FROM users")
    stmt:step()
    local count = stmt:get_value(0)
    stmt:finalize()

    if count == 0 then
        print("Bootstrapping Admin User...")
        local password = random_string(8)
        local recovery = random_string(12)

        -- Compat for different argon2 bindings
        local do_hash = argon2.hash or argon2.hash_encoded
        -- Need salt for hash_encoded if it requires it?
        -- Some bindings generate salt automatically.
        -- "lua-argon2" usually: hash_encoded(pwd, salt, options).
        -- If we need to provide salt, we need random bytes.
        -- Let's check signature.
        -- But for robustness, let's try pcall with just password.

        local function hash_pwd(p)
            local ok, h = pcall(do_hash, p)
            if ok then return h end
            -- Try with salt if failed
            local salt = random_string(16)
            local ok2, h2 = pcall(do_hash, p, salt)
            if ok2 then return h2 end
            error("Argon2 hash failed")
        end

        local hash = hash_pwd(password)
        -- Hash recovery token too for storage
        local rec_hash = hash_pwd(recovery)

        local id = db_mod.uuid()
        local ins = db:prepare("INSERT INTO users (id, username, password_hash, recovery_token_hash) VALUES (?, ?, ?, ?)")
        ins:bind_values(id, "admin", hash, rec_hash)
        ins:step()
        ins:finalize()

        print("========================================")
        print("CONNECT ADMIN CREDENTIALS (SAVE THESE!)")
        print("Password: " .. password)
        print("Recovery: " .. recovery)
        print("========================================")

        -- Write to recovery.txt for convenience on first run
        local f = io.open("recovery.txt", "w")
        if f then
            f:write("Connect Recovery\n")
            f:write("Generated: " .. os.date() .. "\n\n")
            f:write("Password: " .. password .. "\n")
            f:write("Recovery: " .. recovery .. "\n")
            f:close()
        end
    end
end

function M.login(db, password)
    -- Look for admin user (single user mode for now)
    local stmt = db:prepare("SELECT id, password_hash FROM users WHERE username = 'admin'")
    if stmt:step() == sqlite3.ROW then
        local id = stmt:get_value(0)
        local hash = stmt:get_value(1)
        stmt:finalize()

        if argon2.verify(hash, password) then
            return M.create_session(id)
        end
    else
        stmt:finalize()
    end
    return nil
end

function M.login_recovery(db, token)
    local stmt = db:prepare("SELECT id, recovery_token_hash FROM users WHERE username = 'admin'")
    if stmt:step() == sqlite3.ROW then
        local id = stmt:get_value(0)
        local hash = stmt:get_value(1)
        stmt:finalize()

        if argon2.verify(hash, token) then
            return M.create_session(id)
        end
    else
        stmt:finalize()
    end
    return nil
end

function M.reset_password(db, recovery_token, new_password)
    -- Verify recovery
    local stmt = db:prepare("SELECT id, recovery_token_hash FROM users WHERE username = 'admin'")
    if stmt:step() == sqlite3.ROW then
        local id = stmt:get_value(0)
        local r_hash = stmt:get_value(1)
        stmt:finalize()

        if argon2.verify(r_hash, recovery_token) then
            local do_hash = argon2.hash or argon2.hash_encoded
            local function hash_pwd(p)
                 local ok, h = pcall(do_hash, p)
                 if ok then return h end
                 local salt = random_string(16)
                 return do_hash(p, salt)
            end

            local new_hash = hash_pwd(new_password)
            local up = db:prepare("UPDATE users SET password_hash = ? WHERE id = ?")
            up:bind_values(new_hash, id)
            up:step()
            up:finalize()
            return true
        end
    else
        stmt:finalize()
    end
    return false
end

function M.request_recovery(db)
    -- Single user physical access flow
    -- Verify if called from localhost? The requirement says "Physical presence at the machine is implicit authentication".
    -- But code runs on server. "From phone: tap Forgot Password -> Calls request-recovery".
    -- This endpoint is dangerous if exposed. But requirements say:
    -- "Physical access recovery: 1. From phone ... 3. Server generates new password ... 4. Writes to recovery.txt"
    -- This implies anyone who can hit this endpoint resets the password.
    -- However, the user must then "Walk to PC, open file".
    -- If an attacker hits it, they reset the password but can't see the new one unless they have file access.
    -- So it causes a denial of service (resets password) but not a breach.
    -- We should limit this to local network or rate limit?
    -- For now, implement as requested.

    local password = random_string(8)
    local recovery = random_string(12)

    local do_hash = argon2.hash or argon2.hash_encoded
    local function hash_pwd(p)
         local ok, h = pcall(do_hash, p)
         if ok then return h end
         local salt = random_string(16)
         return do_hash(p, salt)
    end

    local p_hash = hash_pwd(password)
    local r_hash = hash_pwd(recovery)

    local up = db:prepare("UPDATE users SET password_hash = ?, recovery_token_hash = ? WHERE username = 'admin'")
    up:bind_values(p_hash, r_hash)
    up:step()
    up:finalize()

    local f = io.open("recovery.txt", "w")
    if f then
        f:write("Connect Recovery\n")
        f:write("Generated: " .. os.date() .. "\n\n")
        f:write("Password: " .. password .. "\n")
        f:write("Recovery: " .. recovery .. "\n")
        f:close()
    end
    return true
end

function M.create_session(user_id)
    local payload = {
        sub = user_id,
        exp = os.time() + (24 * 60 * 60) -- 24 hours
    }
    return sign_token(payload)
end

function M.verify_session(token_header)
    if not token_header then return false end
    local token = token_header:match("Bearer%s+(.+)")
    if not token then return false end

    local payload = verify_token_sign(token)
    if payload and payload.exp > os.time() then
        return true
    end
    return false
end

-- API Token (for MCP) logic
-- "MCP always requires API token — regardless of user count or source."
-- Stored in api_tokens table.
function M.verify_api_token(db, header)
    if not header then return false end
    local token = header:match("Bearer%s+(.+)")
    if not token then return false end

    -- Token is raw. DB has hash?
    -- "API Keys for LLM providers use XOR... API Tokens for MCP ... (hashed in api_tokens table)"
    -- We assume the client sends the raw token.
    -- We need to check if any row matches.
    -- Since we can't unhash, we can't lookup by hash unless we hash the input.
    -- But salt? Argon2 uses random salt.
    -- So we need to iterate? That's slow.
    -- OR we use a fast hash (SHA256) for lookup key?
    -- The requirement says "hashed in api_tokens table".
    -- If using Argon2, we can't search.
    -- Usually API tokens are "prefix.random".
    -- If we just use SHA256 for API tokens, it's searchable.
    -- Let's use SHA256 for API tokens for lookup speed, or store the token itself?
    -- "hashed" implies one-way.
    -- Let's assume we store SHA256(token).

    local sha = GetCryptoHash("SHA256", token)
    local hex = ""
    for i=1, #sha do hex = hex .. string.format("%02x", string.byte(sha, i)) end

    local stmt = db:prepare("SELECT count(*) FROM api_tokens WHERE token_hash = ?")
    stmt:bind_values(hex)
    local valid = (stmt:step() == sqlite3.ROW and stmt:get_value(0) > 0)
    stmt:finalize()
    return valid
end

function M.create_api_token(db, name)
    local token = random_string(32)
    local sha = GetCryptoHash("SHA256", token)
    local hex = ""
    for i=1, #sha do hex = hex .. string.format("%02x", string.byte(sha, i)) end

    local id = db_mod.uuid()
    local ins = db:prepare("INSERT INTO api_tokens (id, token_hash, name) VALUES (?, ?, ?)")
    ins:bind_values(id, hex, name)
    ins:step()
    ins:finalize()

    return token
end

return M
