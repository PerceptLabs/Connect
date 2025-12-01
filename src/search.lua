local M = {}

-- Simple Search Parser and Engine
-- Supports: "exact phrase", -exclude, file_type:md, query terms

function M.parse_query(query)
    local terms = {}
    local phrases = {}
    local excludes = {}
    local filters = {}

    -- 1. Extract quoted phrases
    local function extract_phrases(q)
        for phrase in q:gmatch('"(.-)"') do
            table.insert(phrases, phrase)
        end
        return q:gsub('".-"', '') -- Remove phrases from query
    end

    query = extract_phrases(query)

    -- 2. Extract others
    for token in query:gmatch("%S+") do
        if token:match("^%-") then
            -- Exclude
            table.insert(excludes, token:sub(2))
        elseif token:match(":") then
            -- Filter (key:value)
            local k, v = token:match("^(.-):(.+)$")
            if k and v then
                filters[k] = v
            end
        else
            -- Normal term
            table.insert(terms, token)
        end
    end

    return {
        terms = terms,
        phrases = phrases,
        excludes = excludes,
        filters = filters
    }
end

function M.search(db, raw_query)
    local parsed = M.parse_query(raw_query)
    local results = {}

    -- SQL Construction
    -- We'll search 'documents' and 'chunks' (via chunks table or chunk_fts)

    -- If we have filters like file_type (extension), handle them.
    local sql_where = "WHERE 1=1"
    local params = {}

    if parsed.filters.file_type then
        sql_where = sql_where .. " AND d.file_path LIKE ?"
        table.insert(params, "%." .. parsed.filters.file_type)
    end

    -- Search logic:
    -- 1. Full text search on chunks.
    -- 2. Check exclusions.
    -- 3. Check phrases.

    -- We select from chunks joined with documents.
    local sql = [[
        SELECT c.content, c.label, d.file_path, d.id as doc_id, c.id as chunk_id
        FROM chunks c
        JOIN document_versions dv ON c.document_version_id = dv.id
        JOIN documents d ON dv.document_id = d.id
    ]] .. sql_where

    -- This is a naive full scan if we don't use FTS5.
    -- If FTS5 is enabled (Purpose-Built), we should use chunk_fts.
    -- But let's assume standard generic SQL for robustness as per plan.
    -- Or use LIKE for terms.

    -- Optimization: Construct a LIKE clause for each term.
    for _, term in ipairs(parsed.terms) do
        sql = sql .. " AND c.content LIKE ?"
        table.insert(params, "%" .. term .. "%")
    end

    -- Run query
    local stmt = db:prepare(sql)
    stmt:bind_values(table.unpack(params))

    for row in stmt:nrows() do
        local content = row.content
        local valid = true

        -- Check phrases (exact match case sensitive or insensitive?)
        -- Let's do case insensitive for usability.
        for _, phrase in ipairs(parsed.phrases) do
            if not content:lower():find(phrase:lower(), 1, true) then
                valid = false
                break
            end
        end

        -- Check excludes
        if valid then
            for _, excl in ipairs(parsed.excludes) do
                if content:lower():find(excl:lower(), 1, true) then
                    valid = false
                    break
                end
            end
        end

        if valid then
            table.insert(results, row)
        end
    end
    stmt:finalize()

    -- Ranking?
    -- Naive ranking: count occurrences of terms.
    -- Or just return list.

    return results
end

return M
