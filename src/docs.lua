local sqlite3 = require("lsqlite3")
local tokenizer = require("src.tokenizer")
local db_utils = require("src.db")
local llm_mod = require("src.llm")
local M = {}

function M.commit(db, workspace_id, file_path, content, message, author_type, author_id)
    print("Committing: " .. file_path)
    -- Start Transaction
    db:exec("BEGIN TRANSACTION;")

    local doc_id
    local current_version_num = 0

    -- 1. Check if document exists
    local stmt = db:prepare("SELECT id, current_version_id FROM documents WHERE workspace_id = ? AND file_path = ?")
    stmt:bind_values(workspace_id, file_path)
    local row = stmt:step()
    if row == sqlite3.ROW then
        doc_id = stmt:get_value(0)
        stmt:finalize()

        local v_stmt = db:prepare("SELECT COUNT(*) FROM document_versions WHERE document_id = ?")
        v_stmt:bind_values(doc_id)
        v_stmt:step()
        current_version_num = v_stmt:get_value(0)
        v_stmt:finalize()
    else
        stmt:finalize()
        -- Create Document
        doc_id = db_utils.uuid()
        print("Creating new doc: " .. doc_id)
        local ins = db:prepare("INSERT INTO documents (id, workspace_id, file_path) VALUES (?, ?, ?)")
        ins:bind_values(doc_id, workspace_id, file_path)
        if ins:step() ~= sqlite3.DONE then
            error("DB Error (Insert Doc): " .. db:errmsg())
        end
        ins:finalize()
    end

    -- 2. Create Version
    local version_id = db_utils.uuid()
    local next_version_num = current_version_num + 1

    local ins_v = db:prepare([[
        INSERT INTO document_versions
        (id, document_id, content, commit_message, author_type, author_id, version_number)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]])
    ins_v:bind_values(version_id, doc_id, content, message, author_type, author_id, next_version_num)
    if ins_v:step() ~= sqlite3.DONE then
        error("DB Error (Insert Version): " .. db:errmsg())
    end
    ins_v:finalize()

    -- 3. Update Document HEAD
    local up_d = db:prepare("UPDATE documents SET current_version_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
    up_d:bind_values(version_id, doc_id)
    if up_d:step() ~= sqlite3.DONE then
        error("DB Error (Update HEAD): " .. db:errmsg())
    end
    up_d:finalize()

    -- 4. Chunking
    local chunks = {}
    local current_chunk = { label = "Intro", lines = {} }

    for line in content:gmatch("([^\r\n]*)\r?\n?") do
        local header = line:match("^(#+)%s+(.*)")
        if header then
            if #current_chunk.lines > 0 then
                table.insert(chunks, {
                    label = current_chunk.label,
                    content = table.concat(current_chunk.lines, "\n")
                })
            end
            current_chunk = { label = line, lines = {line} }
        else
            table.insert(current_chunk.lines, line)
        end
    end
    if #current_chunk.lines > 0 then
        table.insert(chunks, {
            label = current_chunk.label,
            content = table.concat(current_chunk.lines, "\n")
        })
    end

    -- 5. Insert Chunks & FTS Shim
    local ins_c = db:prepare("INSERT INTO chunks (document_version_id, content, label, token_count) VALUES (?, ?, ?, ?)")
    local ins_fts = db:prepare("INSERT INTO chunk_fts (rowid, content, label, document_version_id, token_count) VALUES (?, ?, ?, ?, ?)")

    for _, chunk in ipairs(chunks) do
        local tokens = tokenizer.estimate_tokens(chunk.content)
        ins_c:bind_values(version_id, chunk.content, chunk.label, tokens)
        ins_c:step()
        local chunk_rowid = ins_c:last_insert_rowid()
        ins_c:reset()

        -- Insert into Shim table (Explicit token_count)
        ins_fts:bind_values(chunk_rowid, chunk.content, chunk.label, version_id, tokens)
        ins_fts:step()
        ins_fts:reset()
    end

    ins_c:finalize()
    ins_fts:finalize()

    db:exec("COMMIT;")

    -- Write to Repo (Push)
    if author_type ~= "external_sync" then
        local full_path = "repo/" .. file_path
        local dir = full_path:match("(.+)/[^/]+$")
        if dir then
            if unix and unix.makedirs then
                unix.makedirs(dir, 0755)
            else
                os.execute("mkdir -p " .. dir)
            end
        end
        local f = io.open(full_path, "w")
        if f then
            f:write(content)
            f:close()
        end
    end

    -- Summarization Trigger (v1.2)
    -- Trigger every 50 versions to keep history condensed
    if next_version_num > 0 and next_version_num % 50 == 0 then
        print("Triggering summarization for " .. doc_id)

        -- Find maintenance peer (Local/Ollama preferred)
        local peer = nil
        local stmt = db:prepare("SELECT * FROM peers WHERE provider = 'ollama' AND is_active = 1 LIMIT 1")
        if stmt:step() == sqlite3.ROW then
             peer = stmt:get_named_values()
        end
        stmt:finalize()

        local summary_text = "Summary placeholder (No local peer found)"

        if peer then
             local prompt = "Summarize the evolution of this document from version " .. (next_version_num - 50) .. " to " .. next_version_num
             local res = llm_mod.generate(peer, {{role="user", content=prompt}}, {})
             if res and res.content then
                 summary_text = res.content
             end
        end

        local sum_id = db_utils.uuid()
        local sum_stmt = db:prepare([[
            INSERT OR IGNORE INTO document_summaries
            (id, document_id, version_range_start, version_range_end, summary_content, summary_tokens)
            VALUES (?, ?, ?, ?, ?, ?)
        ]])
        local tokens = tokenizer.estimate_tokens(summary_text)
        sum_stmt:bind_values(sum_id, doc_id, next_version_num - 50, next_version_num, summary_text, tokens)
        sum_stmt:step()
        sum_stmt:finalize()
    end

    return { version_id = version_id, version_number = next_version_num }
end

return M
