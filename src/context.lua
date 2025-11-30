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
        -- FTS Shim (LIKE)
        local sql = [[
            SELECT rowid, content, label, token_count, document_version_id
            FROM chunk_fts
            WHERE content LIKE ?
        ]]

        local search_stmt = db:prepare(sql)
        search_stmt:bind_values("%" .. query .. "%")

        for row in search_stmt:nrows() do
            if active_versions[row.document_version_id] then
                if current_tokens + row.token_count <= max_tokens then
                    table.insert(chunks, {
                        id = row.rowid,
                        content = row.content,
                        label = row.label,
                        token_count = row.token_count,
                        rank = "fts_shim" -- BM25 not avail
                    })
                    current_tokens = current_tokens + row.token_count
                else
                    break
                end
            end
        end
        search_stmt:finalize()
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
