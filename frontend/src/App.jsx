import { useState, useEffect } from 'react';
import WorkspaceChat from './pages/WorkspaceChat';
import PeerNetwork from './pages/PeerNetwork';
import { Sidebar } from './components/Sidebar';
import { ConflictModal } from './components/ConflictModal';
import { api } from './utils/api';

function App() {
  const [view, setView] = useState('chat');
  const [workspaceId, setWorkspaceId] = useState(null);
  const [conflict, setConflict] = useState(null);

  useEffect(() => {
    const i = setInterval(() => {
        api.syncStatus().then(res => {
            if (res.conflicts && res.conflicts.length > 0) {
                setConflict(res.conflicts[0]);
            }
        }).catch(console.error);
    }, 5000);
    return () => clearInterval(i);
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
        />
        <div className="flex-1 flex overflow-hidden">
            {view === 'chat' ? (
                <WorkspaceChat workspaceId={workspaceId} setWorkspaceId={setWorkspaceId} />
            ) : (
                <PeerNetwork />
            )}
        </div>
        {conflict && <ConflictModal conflict={conflict} onResolve={handleResolve} />}
    </div>
  );
}

export default App;
