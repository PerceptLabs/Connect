local dmp = require("src.diff_match_patch")
local M = {}

-- Standard Git/Unix Conflict Markers
local MARKER_LOCAL = "<<<<<<< LOCAL"
local MARKER_BASE  = "||||||| BASE"
local MARKER_SEP   = "======="
local MARKER_REMOTE = ">>>>>>> REMOTE"

function M.diff3_merge(local_text, base_text, remote_text)
    -- This implements a 3-way merge logic.
    -- Since we only have a 2-way diff (dmp), we need to simulate 3-way.
    -- Strategy:
    -- 1. Diff Base -> Local
    -- 2. Diff Base -> Remote
    -- 3. Merge the two diff sets.

    local diff1 = dmp.diff_main(base_text, local_text)
    local diff2 = dmp.diff_main(base_text, remote_text)

    dmp.diff_cleanupSemantic(diff1)
    dmp.diff_cleanupSemantic(diff2)

    -- We need to walk both diffs aligned to the Base text.
    -- This is complex.
    -- Alternatively, use the diff_match_patch 'patch' logic which applies patches.
    -- But the requirements said "no patch/match".
    -- So we must manually align.

    -- Let's iterate over the Base text chunks.
    -- But diffs are not chunked by base lines necessarily.

    -- Simplified Merge Algorithm:
    -- 1. Chunkify based on lines? (Easier for code, but Connect is text)
    --    The prompt says "text merging".
    -- 2. Let's try to map changes to indices in Base.

    -- Actually, if we use the LCS-based diff I implemented:
    -- It generates a sequence of Equal/Insert/Delete.

    -- Let's maintain pointers.
    -- We want to construct a Result string.

    local result = {}
    local conflicts = {}
    local has_conflicts = false

    -- Align diffs is hard without a specific tool.
    -- However, "diff3" is standard.
    -- Let's assume we can detect if both modify the same region.

    -- Naive approach:
    -- If Base->Local has change at index I, and Base->Remote has change at index I, it's a conflict (unless identical).

    -- Let's map diffs to "Operations on Base".
    -- Op: {start, end, type, content}

    local function map_ops(diffs)
        local ops = {}
        local base_idx = 1
        for _, d in ipairs(diffs) do
            local op = d[1]
            local text = d[2]
            local len = #text

            if op == dmp.DIFF_EQUAL then
                base_idx = base_idx + len
            elseif op == dmp.DIFF_DELETE then
                -- Deletion from Base
                table.insert(ops, {start=base_idx, count=len, type="del", text=text})
                base_idx = base_idx + len
            elseif op == dmp.DIFF_INSERT then
                -- Insertion (at current base_idx)
                table.insert(ops, {start=base_idx, count=0, type="ins", text=text})
            end
        end
        return ops
    end

    local ops1 = map_ops(diff1)
    local ops2 = map_ops(diff2)

    -- Sort ops by start index? They are already sorted by nature of diff walk.

    -- Now merge ops.
    -- We reconstruct the text from Base, applying ops.
    -- If ops overlap, conflict.

    local merged = ""
    local base_cursor = 1
    local op1_idx = 1
    local op2_idx = 1

    -- Helper to get next op
    local function peek(ops, idx) return ops[idx] end

    while base_cursor <= (#base_text + 1) do
        local o1 = peek(ops1, op1_idx)
        local o2 = peek(ops2, op2_idx)

        -- If no more ops, append rest of base (or handle remaining inserts at EOF)
        if not o1 and not o2 then
             if base_cursor <= #base_text then
                merged = merged .. base_text:sub(base_cursor)
             end
             break
        end

        -- Check if ops are relevant to current cursor
        -- Inserts happen at base_cursor. Deletes start at base_cursor.

        local active1 = o1 and o1.start == base_cursor
        local active2 = o2 and o2.start == base_cursor

        if not active1 and not active2 then
            -- Advance base
            local next_stop = (#base_text + 2)
            if o1 then next_stop = math.min(next_stop, o1.start) end
            if o2 then next_stop = math.min(next_stop, o2.start) end

            merged = merged .. base_text:sub(base_cursor, next_stop - 1)
            base_cursor = next_stop

        elseif active1 and not active2 then
            -- Apply local change
            if o1.type == "ins" then
                merged = merged .. o1.text
            elseif o1.type == "del" then
                -- Skip base text
                base_cursor = base_cursor + o1.count
            end
            op1_idx = op1_idx + 1

        elseif not active1 and active2 then
            -- Apply remote change
            if o2.type == "ins" then
                merged = merged .. o2.text
            elseif o2.type == "del" then
                base_cursor = base_cursor + o2.count
            end
            op2_idx = op2_idx + 1

        else
            -- Both active. Conflict?
            -- 1. If both insert: Conflict (unless same text)
            -- 2. If both delete: Overlap deletion. (If same range, ok. If different, merge deletions?)
            -- 3. One insert, one delete: Conflict (Mixed edit)

            if o1.type == "ins" and o2.type == "ins" then
                if o1.text == o2.text then
                    merged = merged .. o1.text
                else
                    has_conflicts = true
                    merged = merged .. "\n" .. MARKER_LOCAL .. "\n" .. o1.text .. "\n" .. MARKER_SEP .. "\n" .. o2.text .. "\n" .. MARKER_REMOTE .. "\n"
                    table.insert(conflicts, {type="conflict", local_text=o1.text, remote_text=o2.text})
                end
                op1_idx = op1_idx + 1
                op2_idx = op2_idx + 1

            elseif o1.type == "del" and o2.type == "del" then
                -- Overlapping delete.
                -- Maximize deletion.
                local end1 = o1.start + o1.count
                local end2 = o2.start + o2.count
                local max_end = math.max(end1, end2)
                local consume = max_end - base_cursor
                base_cursor = base_cursor + consume
                op1_idx = op1_idx + 1
                op2_idx = op2_idx + 1

            else
                -- Mixed
                has_conflicts = true
                local l_txt = (o1.type == "ins") and o1.text or "" -- For delete, local text is empty (deletion)
                local r_txt = (o2.type == "ins") and o2.text or ""

                -- Wait, if it's a delete, we show what?
                -- Standard git diff3 shows the *Base* content usually.
                -- But here we just want to show "Local wants X" vs "Remote wants Y".
                -- If Local deletes "A", Local wants "". Remote keeps "A" (no op) or modifies "A".
                -- If Remote keeps "A" (no op), then active2 would be false!
                -- But here active2 is TRUE, so Remote is ALSO doing something.

                -- Case: Local delete, Remote insert.
                -- Local wants to delete Base[C]. Remote wants to insert "R" at C.
                -- Conflict? Usually not. Insert happens before delete? Or after?
                -- Ambiguous.

                merged = merged .. "\n" .. MARKER_LOCAL .. "\n" .. l_txt .. "\n" .. MARKER_SEP .. "\n" .. r_txt .. "\n" .. MARKER_REMOTE .. "\n"

                -- Consume deletions
                if o1.type == "del" then base_cursor = base_cursor + o1.count end
                if o2.type == "del" then
                    -- If we already consumed base for o1, we might double consume?
                    -- We need to be careful about base_cursor updates.
                    -- If both delete, we handled above.
                    -- If one deletes, the other inserts. The insert doesn't move base_cursor.
                    -- So we are fine.
                end

                op1_idx = op1_idx + 1
                op2_idx = op2_idx + 1
            end
        end
    end

    return {
        merged = merged,
        has_conflicts = has_conflicts,
        conflicts = conflicts
    }
end

return M
