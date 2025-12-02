// Frontend WebSocket Client

let socket = null;
let listeners = [];
let reconnectTimer = null;

const API_WS = import.meta.env.DEV ? 'ws://localhost:8080/api/ws' : ((window.location.protocol === 'https:' ? 'wss://' : 'ws://') + window.location.host + '/api/ws');

export const ws = {
    connect: () => {
        if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) return;

        // Add token to query param
        const token = sessionStorage.getItem('connect_auth');
        const url = token ? `${API_WS}?token=${encodeURIComponent(token)}` : API_WS;

        socket = new WebSocket(url);

        socket.onopen = () => {
            console.log("WS Connected");
            if (reconnectTimer) clearTimeout(reconnectTimer);
            ws.emit("status", "connected");
        };

        socket.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                listeners.forEach(cb => cb(data));
            } catch(e) {
                console.error("WS Parse Error", e);
            }
        };

        socket.onclose = () => {
            console.log("WS Closed, reconnecting...");
            ws.emit("status", "disconnected");
            reconnectTimer = setTimeout(ws.connect, 3000); // Exponential backoff in real app
        };

        socket.onerror = (err) => {
            console.error("WS Error", err);
        };
    },

    subscribe: (callback) => {
        listeners.push(callback);
        return () => {
            listeners = listeners.filter(l => l !== callback);
        };
    },

    emit: (type, payload) => {
        // Only for internal status updates in this shim
        // In real app, we might send to server.
        if (type === "status") {
             listeners.forEach(cb => cb({ type: "connection_status", status: payload }));
        }
    }
};
