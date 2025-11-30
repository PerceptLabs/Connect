local docs = require("src.docs")
local M = {}

local function parse_time(iso)
    if not iso then return 0 end
    local Y, m, d, H, M, S = iso:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if not Y then return 0 end
    return os.time({year=Y, month=m, day=d, hour=H, min=M, sec=S})
end

function M.check_sync(db)
  local updates = 0
  local conflicts = {}

  local stmt = db:prepare([[
    SELECT d.id, d.workspace_id, d.file_path, v.content as current_content, d.updated_at as db_mtime, d.current_version_id
    FROM documents d
    LEFT JOIN document_versions v ON d.current_version_id = v.id
  ]])

  for row in stmt:nrows() do
    local full_path = "repo/" .. row.file_path
    local f = io.open(full_path, "r")
    if f then
      local content = f:read("*a")
      f:close()

      -- Get file mtime
      local file_mtime = 0
      if unix and unix.stat then
          local st = unix.stat(full_path)
          if st then file_mtime = st.mtime end
      end

      if content ~= row.current_content then
         -- Conflict Detection: content changed AND timestamps mismatch (implying concurrent edit)
         -- We allow 2 second skew to avoid false positives
         local db_epoch = parse_time(row.db_mtime)
         local skew = math.abs(file_mtime - db_epoch)

         if skew > 2 then
             -- Timestamps diverge => Conflict
             table.insert(conflicts, {
                document_id = row.id,
                workspace_id = row.workspace_id,
                file_path = row.file_path,
                user_content = content,
                ai_content = row.current_content,
                ancestor_version_id = row.current_version_id
             })
         else
             -- Normal Sync (Timestamps align or close enough)
             print("Sync detected change: " .. full_path)
             docs.commit(db, row.workspace_id, row.file_path, content, "External Sync", "external_sync", "watcher")
             updates = updates + 1
         end
      end
    end
  end
  stmt:finalize()

  return { synced = updates, conflicts = conflicts }
end

return M
