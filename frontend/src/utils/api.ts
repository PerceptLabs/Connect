const API_BASE = import.meta.env.DEV ? 'http://localhost:8080/api' : '/api';

// Simple token management - in real app, might want to store in localStorage/sessionStorage
let authToken = sessionStorage.getItem('connect_auth') || '';

// Callback to trigger login UI
let onUnauthorized = () => {};

const getHeaders = (extra = {}) => {
  const headers = { ...extra };
  if (authToken) {
    // Check if token already has Bearer prefix or not
    // The server expects "Bearer <token>" usually?
    // auth.lua: "Bearer " .. token or just token match?
    // auth.lua: verify_session checks `token_header:match("Bearer%s+(.+)")`
    // So we must prefix.
    // If we set authToken as just the token string, prefix here.
    if (authToken.startsWith('Bearer ')) {
         headers['Authorization'] = authToken;
    } else {
         headers['Authorization'] = `Bearer ${authToken}`;
    }
  }
  return headers;
};

// Internal fetch wrapper to handle JSON response and errors
const request = async (url, options = {}) => {
    const res = await fetch(url, {
        ...options,
        headers: getHeaders(options.headers)
    });

    if (res.status === 401) {
        onUnauthorized();
        // Return empty or error to stop downstream
        throw new Error("Unauthorized");
    }

    return res.json();
};

export const api = {
  setUnauthorizedHandler: (fn) => { onUnauthorized = fn; },
  // Methods to set/get token (useful if we implement login UI or auto-discovery handshake)
  setToken: (t) => { authToken = t; },
  getToken: () => authToken,

  get: (url) => request(`${API_BASE}${url}`),
  post: (url, body) => request(`${API_BASE}${url}`, { method: 'POST', body: JSON.stringify(body), headers: {'Content-Type': 'application/json'} }),
  request: (url, opts) => request(`${API_BASE}${url}`, opts), // Expose generic request for flexible usage

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
