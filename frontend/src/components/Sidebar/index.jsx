import { useState, useEffect } from 'react';
import { api } from '../../utils/api';
import { Plus, MessageSquare, Server, MessageCircle } from 'lucide-react';
import AdvancedSearch from '../AdvancedSearch';

export function Sidebar({ workspaceId, setWorkspaceId, activeView, onNavigate, threadId, setThreadId }) {
    const [workspaces, setWorkspaces] = useState([]);
    const [threads, setThreads] = useState([]);
    const [showNewThread, setShowNewThread] = useState(false);
    const [newThreadName, setNewThreadName] = useState("");

    useEffect(() => {
        api.getWorkspaces().then(res => {
            const ws = (res && Array.isArray(res.workspaces)) ? res.workspaces : [];
            setWorkspaces(ws);
            if (ws.length > 0 && !workspaceId) {
                setWorkspaceId(ws[0].id);
            }
        }).catch(err => {
            console.error(err);
            setWorkspaces([]);
        });
    }, []);

    useEffect(() => {
        if(workspaceId) {
            api.getThreads(workspaceId).then(res => {
                const ts = (res && Array.isArray(res.threads)) ? res.threads : [];
                setThreads(ts);
            }).catch(err => {
                console.error(err);
                setThreads([]);
            });
        }
    }, [workspaceId]);

    const handleCreateThread = () => {
        if (!newThreadName.trim() || !workspaceId) return;
        api.createThread(workspaceId, newThreadName).then(res => {
            setThreads([res, ...threads]);
            setThreadId(res.id);
            setShowNewThread(false);
            setNewThreadName("");
        });
    };

    const handleImport = (e) => {
        const file = e.target.files[0];
        if (file) {
            api.importWorkspace(file).then(() => {
                alert("Import successful! Reloading...");
                window.location.reload();
            }).catch(err => alert("Import failed: " + err));
        }
    };

    return (
        <div className="w-64 bg-gray-900 text-white flex flex-col h-full border-r border-gray-800 flex-shrink-0">
            <div className="p-4 border-b border-gray-800">
                <div className="text-xl font-bold tracking-tight mb-6 flex items-center gap-2">
                    <div className="w-6 h-6 bg-blue-600 rounded flex items-center justify-center text-[10px]">C</div>
                    Connect v2.0
                </div>

                <div className="mb-6">
                    <AdvancedSearch />
                </div>

                {/* Main Nav */}
                <div className="space-y-1 mb-6">
                    <div
                        onClick={() => onNavigate && onNavigate('chat')}
                        className={`flex items-center gap-2 p-2 rounded cursor-pointer text-sm font-medium transition-colors ${activeView === 'chat' ? 'bg-gray-800 text-white' : 'text-gray-400 hover:bg-gray-800 hover:text-gray-200'}`}
                    >
                        <MessageCircle size={18} /> Chat
                    </div>
                    <div
                        onClick={() => onNavigate && onNavigate('peers')}
                        className={`flex items-center gap-2 p-2 rounded cursor-pointer text-sm font-medium transition-colors ${activeView === 'peers' ? 'bg-gray-800 text-white' : 'text-gray-400 hover:bg-gray-800 hover:text-gray-200'}`}
                    >
                        <Server size={18} /> Peer Network
                    </div>
                </div>

                <div className="mb-6 flex gap-2">
                     <button
                        onClick={() => workspaceId && api.exportWorkspace(workspaceId)}
                        className="flex-1 bg-gray-800 text-xs py-1 rounded hover:bg-gray-700 text-gray-300"
                        title="Export Workspace"
                     >
                        Export
                     </button>
                     <label className="flex-1 bg-gray-800 text-xs py-1 rounded hover:bg-gray-700 text-gray-300 text-center cursor-pointer">
                        Import
                        <input type="file" className="hidden" accept=".json" onChange={handleImport} />
                     </label>
                </div>

                {activeView === 'chat' && (
                    <>
                        <div className="text-xs text-gray-500 uppercase font-semibold mb-2">Workspace</div>
                        <select
                            className="w-full bg-gray-800 border border-gray-700 rounded p-2 text-sm focus:outline-none focus:border-blue-500 text-gray-300"
                            value={workspaceId || ""}
                            onChange={e => setWorkspaceId(e.target.value)}
                        >
                            {workspaces.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
                        </select>
                    </>
                )}
            </div>

            {activeView === 'chat' && (
                <div className="flex-1 overflow-y-auto p-2">
                    <div className="text-xs text-gray-500 uppercase font-semibold mb-2 px-2 mt-4 flex justify-between items-center">
                        <span>Threads</span>
                        <Plus
                            size={12}
                            className="cursor-pointer hover:text-white"
                            onClick={() => setShowNewThread(true)}
                        />
                    </div>

                    {showNewThread && (
                        <div className="px-2 mb-2">
                            <input
                                autoFocus
                                className="w-full bg-gray-800 text-sm text-white border border-blue-500 rounded p-1 mb-1"
                                placeholder="Thread name..."
                                value={newThreadName}
                                onChange={e => setNewThreadName(e.target.value)}
                                onKeyDown={e => e.key === 'Enter' && handleCreateThread()}
                            />
                            <div className="flex gap-2 justify-end text-[10px]">
                                <button onClick={() => setShowNewThread(false)} className="text-gray-400 hover:text-white">Cancel</button>
                                <button onClick={handleCreateThread} className="text-blue-400 hover:text-blue-300">Create</button>
                            </div>
                        </div>
                    )}

                    {threads.map(t => (
                        <div
                            key={t.id}
                            onClick={() => setThreadId(t.id)}
                            className={`flex items-center gap-2 p-2 rounded cursor-pointer text-sm transition-colors ${threadId === t.id ? 'bg-blue-900/30 text-blue-200' : 'text-gray-300 hover:bg-gray-800'}`}
                        >
                            <MessageSquare size={14} className={threadId === t.id ? 'text-blue-400' : 'text-gray-500'} />
                            <div className="truncate">{t.name}</div>
                        </div>
                    ))}
                    {threads.length === 0 && <div className="text-xs text-gray-600 px-2 italic">No threads yet</div>}
                </div>
            )}
        </div>
    );
}
