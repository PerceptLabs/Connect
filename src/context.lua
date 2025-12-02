local M = {}
local sqlite3 = require("lsqlite3")

-- Helper to get keys
local function keys(t)
    local k = {}
    for key, _ in pairs(t) do table.insert(k, key) end
    return k
end

function M.select(db, thread_id, query, max_tokens)
    max_tokens = max_tokens or 4096
    local chunks = {}
    local current_tokens = 0

    -- 1. Get Workspace ID & Active Versions
    -- We assume thread belongs to workspace, documents belong to workspace
    local active_versions = {}
    local stmt = db:prepare([[
        SELECT d.current_version_id
        FROM documents d
        JOIN threads t ON d.workspace_id = t.workspace_id
        WHERE t.id = ? AND d.current_version_id IS NOT NULL
    ]])
    stmt:bind_values(thread_id)
    for row in stmt:nrows() do
        active_versions[row.current_version_id] = true
    end
    stmt:finalize()

    if query and query ~= "" then
        -- FTS Search (Shim or FTS5)
        -- We query chunk_fts. If it's FTS5, we can use MATCH (if we knew it was FTS5).
        -- But since we want to be safe, we might stick to LIKE or try dynamic?
        -- The plan says "Ensure it respects FTS5... via .init.lua".
        -- If FTS5 is active, `chunk_fts` IS a virtual table.
        -- MATCH works on virtual table. LIKE works too but slow.
        -- We should try MATCH if possible.
        -- But we don't pass `fts_available` flag here.
        -- Let's try MATCH and catch error? Or just use LIKE as baseline.
        -- Given requirements "FTS5 with BM25 ranking", we MUST use MATCH if available.
        -- Let's attempt MATCH first, if fail (table not virtual?), fallback?
        -- Actually, if .init.lua created a standard table, MATCH will fail.

        -- Optimized: Try MATCH. If sqlite3 error, fallback to LIKE.
        local has_fts5 = false
        -- We can check if table is virtual?
        -- Or just try.

        local sql_match = [[
            SELECT rowid, content, label, token_count, document_version_id
            FROM chunk_fts
            WHERE content MATCH ?
            ORDER BY rank
        ]]

        local sql_like = [[
            SELECT rowid, content, label, token_count, document_version_id
            FROM chunk_fts
            WHERE content LIKE ?
        ]]

        local function fetch_chunks(stmt, is_match)
             for row in stmt:nrows() do
                -- Join with documents to get document_id (Feature 8.10)
                -- But chunk_fts doesn't have document_id, only version_id.
                -- We need to resolve it.
                -- active_versions keys are version_ids.
                if active_versions[row.document_version_id] then
                    -- Resolve document_id?
                    -- We can cache map of version->doc?
                    -- Or query?
                    -- Better: Join in the main query?
                    -- chunk_fts join document_versions join documents.
                    -- FTS5 joins can be tricky.

                    -- Let's just fetch doc info for the valid chunks.
                    if current_tokens + row.token_count <= max_tokens then
                        -- Get Doc ID
                        local d_stmt = db:prepare("SELECT document_id FROM document_versions WHERE id = ?")
                        d_stmt:bind_values(row.document_version_id)
                        local doc_id
                        if d_stmt:step() == sqlite3.ROW then doc_id = d_stmt:get_value(0) end
                        d_stmt:finalize()

                        table.insert(chunks, {
                            id = row.rowid,
                            content = row.content,
                            label = row.label,
                            token_count = row.token_count,
                            document_id = doc_id, -- Feature 8.10
                            rank = is_match and "bm25" or "fts_shim"
                        })
                        current_tokens = current_tokens + row.token_count
                    else
                        break
                    end
                end
            end
        end

        local search_stmt = db:prepare(sql_match)
        if search_stmt then
             -- Try binding
             local status = pcall(function() search_stmt:bind_values(query) end)
             if status then
                 -- Execute
                 local status_step = pcall(function() fetch_chunks(search_stmt, true) end)
                 search_stmt:finalize()
                 if status_step then return chunks end -- Success
             else
                 search_stmt:finalize()
             end
        end

        -- Fallback
        search_stmt = db:prepare(sql_like)
        search_stmt:bind_values("%" .. query .. "%")
        fetch_chunks(search_stmt, false)
        search_stmt:finalize()
    end

    -- Feature 8.2: Include Summaries if budget allows
    -- If we have space left, include summaries of relevant documents.
    if current_tokens < max_tokens then
        local sum_sql = [[
             SELECT ds.summary_content, ds.summary_tokens, d.id as doc_id, d.file_path
             FROM document_summaries ds
             JOIN documents d ON ds.document_id = d.id
             JOIN threads t ON d.workspace_id = t.workspace_id
             WHERE t.id = ?
             ORDER BY ds.created_at DESC
             LIMIT 5
        ]]
        local s_stmt = db:prepare(sum_sql)
        s_stmt:bind_values(thread_id)
        for row in s_stmt:nrows() do
             if current_tokens + row.summary_tokens <= max_tokens then
                 table.insert(chunks, {
                     id = "summary_" .. row.doc_id,
                     content = "Summary of " .. row.file_path .. ":\n" .. row.summary_content,
                     label = "Summary",
                     token_count = row.summary_tokens,
                     document_id = row.doc_id,
                     rank = "summary"
                 })
                 current_tokens = current_tokens + row.summary_tokens
             end
        end
        s_stmt:finalize()
    end

    return chunks
end

function M.estimate(db, thread_id, query, max_tokens)
    local pinned_tokens = 0
    local fts_tokens = 0
    local summary_tokens = 0
    local chunks_selected = 0
    local pinned_docs = {}

    -- 1. Calculate pinned tokens
    local stmt = db:prepare([[
        SELECT d.id, d.file_path, SUM(c.token_count) as tokens
        FROM pinned_documents pd
        JOIN documents d ON pd.document_id = d.id
        JOIN chunks c ON d.current_version_id = c.document_version_id
        JOIN threads t ON pd.workspace_id = t.workspace_id
        WHERE t.id = ?
        GROUP BY d.id
    ]])
    stmt:bind_values(thread_id)
    for row in stmt:nrows() do
        table.insert(pinned_docs, { id = row.id, file_path = row.file_path, tokens = row.tokens })
        pinned_tokens = pinned_tokens + row.tokens
    end
    stmt:finalize()

    -- 2. Calculate FTS tokens (dry-run)
    local remaining_tokens = max_tokens - pinned_tokens
    local fts_chunks = M.select(db, thread_id, query, remaining_tokens)
    for _, chunk in ipairs(fts_chunks) do
        fts_tokens = fts_tokens + chunk.token_count
        chunks_selected = chunks_selected + 1
    end

    -- 3. Calculate summary tokens if no FTS results
    if #fts_chunks == 0 and (query == "" or not query) then
        local sum_stmt = db:prepare([[
          SELECT SUM(summary_tokens) as tokens
          FROM document_summaries ds
          JOIN documents d ON ds.document_id = d.id
          JOIN threads t ON d.workspace_id = t.workspace_id
          WHERE t.id = ?
        ]])
        sum_stmt:bind_values(thread_id)
        if sum_stmt:step() == sqlite3.ROW then
            summary_tokens = sum_stmt:get_value(0) or 0
        end
        sum_stmt:finalize()
    end

    local total_tokens = pinned_tokens + fts_tokens + summary_tokens
    local utilization_percent = 0
    if max_tokens > 0 then
        utilization_percent = math.floor((total_tokens / max_tokens) * 100)
    end

    return {
        total_tokens = total_tokens,
        pinned_tokens = pinned_tokens,
        fts_tokens = fts_tokens,
        summary_tokens = summary_tokens,
        chunks_selected = chunks_selected,
        utilization_percent = utilization_percent,
        warnings = utilization_percent > 90 and
            {"Token budget " .. utilization_percent .. "% utilized."} or {},
        pinned_documents = pinned_docs,
        top_chunks = fts_chunks -- First few
    }
end

return M
