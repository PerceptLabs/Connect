-- 1. WORKSPACES (Top-level container)
CREATE TABLE IF NOT EXISTS workspaces (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 2. THREADS (Conversations within a workspace)
CREATE TABLE IF NOT EXISTS threads (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id),
  name TEXT NOT NULL,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 3. DOCUMENTS (Files tracked per workspace)
CREATE TABLE IF NOT EXISTS documents (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id),
  file_path TEXT NOT NULL,
  current_version_id TEXT,
  is_pinned BOOLEAN DEFAULT FALSE,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(workspace_id, file_path)
);

-- 4. MESSAGES (Chat history per thread)
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL REFERENCES threads(id),
  role TEXT NOT NULL CHECK(role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  metadata TEXT, -- JSON: { "peerId": "peer_local", "ref_version_ids": ["v1", "v2"] }
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 5. DOCUMENT VERSIONS (Git-like commits)
CREATE TABLE IF NOT EXISTS document_versions (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES documents(id),
  content TEXT NOT NULL,
  commit_message TEXT,
  author_type TEXT,    -- 'user', 'llm', 'external_sync'
  author_id TEXT,
  version_number INTEGER NOT NULL,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 6. CHUNKS (Granular context)
CREATE TABLE IF NOT EXISTS chunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  document_version_id TEXT NOT NULL REFERENCES document_versions(id),
  content TEXT NOT NULL,
  label TEXT,
  token_count INTEGER NOT NULL
);

-- 7. FTS5 INDEX (Deterministic search)
-- SHIM: Using standard table because Redbean stock binary lacks FTS5.
-- In production with custom build, uncomment the VIRTUAL TABLE and remove this.
CREATE TABLE IF NOT EXISTS chunk_fts (
  rowid INTEGER PRIMARY KEY,
  content TEXT,
  label TEXT,
  document_version_id TEXT,
  token_count INTEGER
);
-- CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(
--   content,
--   label,
--   document_version_id UNINDEXED,
--   token_count UNINDEXED
-- );

-- 8. PINNED DOCUMENTS (Session-level overrides)
CREATE TABLE IF NOT EXISTS pinned_documents (
  workspace_id TEXT NOT NULL REFERENCES workspaces(id),
  document_id TEXT NOT NULL REFERENCES documents(id),
  PRIMARY KEY (workspace_id, document_id)
);

-- 9. DOCUMENT SUMMARIES (Knowledge condensation)
CREATE TABLE IF NOT EXISTS document_summaries (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES documents(id),
  version_range_start INTEGER NOT NULL,
  version_range_end INTEGER NOT NULL,
  summary_content TEXT NOT NULL,
  summary_tokens INTEGER NOT NULL,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(document_id, version_range_start, version_range_end)
);

-- 10. CONFLICT VERSIONS (Conflict resolution)
CREATE TABLE IF NOT EXISTS conflict_versions (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES documents(id),
  user_content TEXT NOT NULL,
  ai_content TEXT NOT NULL,
  ancestor_version_id TEXT NOT NULL REFERENCES document_versions(id),
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 11. PEERS (Dynamic Peer Configuration)
CREATE TABLE IF NOT EXISTS peers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,          -- User-friendly name
  provider TEXT NOT NULL,      -- "ollama", "openai", "lmstudio", "anthropic"
  base_url TEXT NOT NULL,      -- e.g., "http://localhost:11434"
  api_key TEXT,               -- Encrypted or stored raw for now
  model_id TEXT NOT NULL,      -- The specific model slug
  context_window INTEGER DEFAULT 4096,
  is_active BOOLEAN DEFAULT 1,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
