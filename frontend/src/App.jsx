import { useState, useEffect } from 'react';
import WorkspaceChat from './pages/WorkspaceChat';
import PeerNetwork from './pages/PeerNetwork';
import { Sidebar } from './components/Sidebar';
import { ConflictModal } from './components/ConflictModal';
import NetworkInfo from './components/NetworkInfo';
import { api } from './utils/api';
import { ws } from './utils/websocket';

function App() {
  const [view, setView] = useState('chat');
  const [workspaceId, setWorkspaceId] = useState(null);
  const [threadId, setThreadId] = useState(null);
  const [conflict, setConflict] = useState(null);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    ws.connect();
    const unsub = ws.subscribe(msg => {
        if (msg.type === "connection_status") {
            setConnected(msg.status === "connected");
        }
        if (msg.type === "conflict") {
            // Server notified us of a conflict
            // Fetch conflict details or just set it if payload has it
             api.syncStatus().then(res => {
                if (res.conflicts && res.conflicts.length > 0) {
                    setConflict(res.conflicts[0]);
                }
            });
        }
        if (msg.type === "sync_update") {
            // Trigger UI refresh?
        }
    });

    // Initial check
    api.syncStatus().then(res => {
        if (res.conflicts && res.conflicts.length > 0) {
            setConflict(res.conflicts[0]);
        }
    }).catch(console.error);

    return () => {
        unsub();
        // Don't close socket on unmount necessarily if App is root, but clean up listeners
    };
  }, []);

  const handleResolve = (action) => {
      if (action === 'overwrite' && conflict) {
          api.commitDoc(conflict.workspace_id, conflict.file_path, conflict.user_content, "Conflict Resolved: Overwrite");
      }
      // 'accept' logic would require fetching remote content and writing to disk,
      // which 'syncStatus' handles next time if we revert local change?
      // For now, just clear modal to unblock UI.
      setConflict(null);
  };

  return (
    <div className="flex h-screen w-full bg-white text-gray-900 font-sans">
        <Sidebar
            activeView={view}
            onNavigate={setView}
            workspaceId={workspaceId}
            setWorkspaceId={setWorkspaceId}
            threadId={threadId}
            setThreadId={setThreadId}
        />
        <div className="flex-1 flex overflow-hidden">
            {view === 'chat' ? (
                <WorkspaceChat
                    workspaceId={workspaceId}
                    setWorkspaceId={setWorkspaceId}
                    threadId={threadId}
                    setThreadId={setThreadId}
                />
            ) : (
                <PeerNetwork />
            )}
        </div>
        {conflict && <ConflictModal conflict={conflict} onResolve={handleResolve} />}
        <NetworkInfo />
    </div>
  );
}

export default App;
