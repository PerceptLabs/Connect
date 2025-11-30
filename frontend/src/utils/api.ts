const API_BASE = import.meta.env.DEV ? 'http://localhost:8080/api' : '/api';

export const api = {
  getWorkspaces: () => fetch(`${API_BASE}/workspaces`).then(r => r.json()),
  createWorkspace: (name) => fetch(`${API_BASE}/workspaces`, { method: 'POST', body: JSON.stringify({ name }), headers: {'Content-Type': 'application/json'} }).then(r => r.json()),
  getThreads: (workspaceId) => fetch(`${API_BASE}/workspaces/${workspaceId}/threads`).then(r => r.json()),
  createThread: (workspaceId, name) => fetch(`${API_BASE}/threads`, { method: 'POST', body: JSON.stringify({ workspace_id: workspaceId, name }), headers: {'Content-Type': 'application/json'} }).then(r => r.json()),

  // Peer Management
  getPeers: () => fetch(`${API_BASE}/peers`).then(r => r.json()),
  createPeer: (peer) => fetch(`${API_BASE}/peers`, { method: 'POST', body: JSON.stringify(peer), headers: {'Content-Type': 'application/json'} }).then(r => r.json()),
  deletePeer: (id) => fetch(`${API_BASE}/peers/${id}`, { method: 'DELETE' }).then(r => r.json()),
  discoverPeer: (provider, baseUrl, apiKey) => fetch(`${API_BASE}/peers/discover`, { method: 'POST', body: JSON.stringify({ provider, base_url: baseUrl, api_key: apiKey }), headers: {'Content-Type': 'application/json'} }).then(r => r.json()),

  selectContext: (threadId, query, maxTokens = 4096) => fetch(`${API_BASE}/context/select`, { method: 'POST', body: JSON.stringify({ thread_id: threadId, query, max_tokens: maxTokens }), headers: {'Content-Type': 'application/json'} }).then(r => r.json()),
  estimateContext: (threadId, query, maxTokens = 4096) => fetch(`${API_BASE}/context/estimate`, { method: 'POST', body: JSON.stringify({ thread_id: threadId, query, max_tokens: maxTokens }), headers: {'Content-Type': 'application/json'} }).then(r => r.json()),
  generate: (peerId, messages, contextChunks) => fetch(`${API_BASE}/llm/generate`, { method: 'POST', body: JSON.stringify({ peer_id: peerId, messages, context_chunks: contextChunks }), headers: {'Content-Type': 'application/json'} }).then(r => r.json()),
  pinDocument: (workspaceId, docId) => fetch(`${API_BASE}/pin`, { method: 'POST', body: JSON.stringify({ workspace_id: workspaceId, document_id: docId }), headers: {'Content-Type': 'application/json'} }).then(r => r.json()),
  unpinDocument: (workspaceId, docId) => fetch(`${API_BASE}/unpin`, { method: 'DELETE', body: JSON.stringify({ workspace_id: workspaceId, document_id: docId }), headers: {'Content-Type': 'application/json'} }).then(r => r.json()),
  getPins: (workspaceId) => fetch(`${API_BASE}/pins?workspace_id=${workspaceId}`).then(r => r.json()),
  syncStatus: () => fetch(`${API_BASE}/sync/status`, { method: 'POST', body: '{}', headers: {'Content-Type': 'application/json'} }).then(r => r.json()),
  commitDoc: (workspaceId, path, content, msg) => fetch(`${API_BASE}/docs/commit`, {
        method: 'POST',
        body: JSON.stringify({workspace_id: workspaceId, file_path: path, content, message: msg}),
        headers: {'Content-Type': 'application/json'}
  }).then(r => r.json())
};
