const API_BASE = import.meta.env.DEV ? 'http://localhost:8080/api' : '/api';

// Simple token management - in real app, might want to store in localStorage/sessionStorage
let authToken = '';

const getHeaders = (extra = {}) => {
  const headers = { ...extra };
  if (authToken) {
    headers['Authorization'] = authToken;
  }
  return headers;
};

// Internal fetch wrapper to handle JSON response and errors
const request = async (url, options = {}) => {
    const res = await fetch(url, {
        ...options,
        headers: getHeaders(options.headers)
    });
    // Check for 401 ?
    return res.json();
};

export const api = {
  // Methods to set/get token (useful if we implement login UI or auto-discovery handshake)
  setToken: (t) => { authToken = t; },

  get: (url) => request(`${API_BASE}${url}`),

  getWorkspaces: () => request(`${API_BASE}/workspaces`),
  createWorkspace: (name) => request(`${API_BASE}/workspaces`, { method: 'POST', body: JSON.stringify({ name }), headers: {'Content-Type': 'application/json'} }),
  getThreads: (workspaceId) => request(`${API_BASE}/workspaces/${workspaceId}/threads`),
  createThread: (workspaceId, name) => request(`${API_BASE}/threads`, { method: 'POST', body: JSON.stringify({ workspace_id: workspaceId, name }), headers: {'Content-Type': 'application/json'} }),

  getMessages: (threadId) => request(`${API_BASE}/threads/${threadId}/messages`),
  sendMessage: (threadId, content, role = 'user', metadata = {}) => request(`${API_BASE}/threads/${threadId}/messages`, { method: 'POST', body: JSON.stringify({ content, role, metadata }), headers: {'Content-Type': 'application/json'} }),

  // Peer Management
  getPeers: () => request(`${API_BASE}/peers`),
  createPeer: (peer) => request(`${API_BASE}/peers`, { method: 'POST', body: JSON.stringify(peer), headers: {'Content-Type': 'application/json'} }),
  deletePeer: (id) => request(`${API_BASE}/peers/${id}`, { method: 'DELETE' }),
  discoverPeer: (provider, baseUrl, apiKey) => request(`${API_BASE}/peers/discover`, { method: 'POST', body: JSON.stringify({ provider, base_url: baseUrl, api_key: apiKey }), headers: {'Content-Type': 'application/json'} }),

  selectContext: (threadId, query, maxTokens = 4096) => request(`${API_BASE}/context/select`, { method: 'POST', body: JSON.stringify({ thread_id: threadId, query, max_tokens: maxTokens }), headers: {'Content-Type': 'application/json'} }),
  estimateContext: (threadId, query, maxTokens = 4096) => request(`${API_BASE}/context/estimate`, { method: 'POST', body: JSON.stringify({ thread_id: threadId, query, max_tokens: maxTokens }), headers: {'Content-Type': 'application/json'} }),
  generate: (peerId, messages, contextChunks) => request(`${API_BASE}/llm/generate`, { method: 'POST', body: JSON.stringify({ peer_id: peerId, messages, context_chunks: contextChunks }), headers: {'Content-Type': 'application/json'} }),
  pinDocument: (workspaceId, docId) => request(`${API_BASE}/pin`, { method: 'POST', body: JSON.stringify({ workspace_id: workspaceId, document_id: docId }), headers: {'Content-Type': 'application/json'} }),
  unpinDocument: (workspaceId, docId) => request(`${API_BASE}/unpin`, { method: 'DELETE', body: JSON.stringify({ workspace_id: workspaceId, document_id: docId }), headers: {'Content-Type': 'application/json'} }),
  getPins: (workspaceId) => request(`${API_BASE}/pins?workspace_id=${workspaceId}`),
  syncStatus: () => request(`${API_BASE}/sync/status`, { method: 'POST', body: '{}', headers: {'Content-Type': 'application/json'} }),
  commitDoc: (workspaceId, path, content, msg) => request(`${API_BASE}/docs/commit`, {
        method: 'POST',
        body: JSON.stringify({workspace_id: workspaceId, file_path: path, content, message: msg}),
        headers: {'Content-Type': 'application/json'}
  }),
  search: (query) => request(`${API_BASE}/search?query=${encodeURIComponent(query)}`),

  exportWorkspace: (workspaceId) => {
      // Trigger download
      window.location.href = `${API_BASE}/backup/export?workspace_id=${workspaceId}`;
  },
  importWorkspace: (file) => {
      return new Promise((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = e => {
              try {
                  const json = JSON.parse(e.target.result);
                  request(`${API_BASE}/backup/import`, {
                      method: 'POST',
                      body: JSON.stringify(json),
                      headers: {'Content-Type': 'application/json'}
                  }).then(resolve).catch(reject);
              } catch(err) {
                  reject("Invalid JSON");
              }
          };
          reader.readAsText(file);
      });
  }
};
