import { useState, useEffect } from 'react';
import { api } from '../../utils/api';
import { Plus, MessageSquare, Server, MessageCircle } from 'lucide-react';

export function Sidebar({ workspaceId, setWorkspaceId, activeView, onNavigate }) {
    const [workspaces, setWorkspaces] = useState([]);
    const [threads, setThreads] = useState([]);

    useEffect(() => {
        api.getWorkspaces().then(res => setWorkspaces(res.workspaces || [])).catch(console.error);
    }, []);

    useEffect(() => {
        if(workspaceId) {
            api.getThreads(workspaceId).then(res => setThreads(res.threads || [])).catch(console.error);
        }
    }, [workspaceId]);

    return (
        <div className="w-64 bg-gray-900 text-white flex flex-col h-full border-r border-gray-800 flex-shrink-0">
            <div className="p-4 border-b border-gray-800">
                <div className="text-xl font-bold tracking-tight mb-6 flex items-center gap-2">
                    <div className="w-6 h-6 bg-blue-600 rounded flex items-center justify-center text-[10px]">C</div>
                    Connect v1.0
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
                        <Plus size={12} className="cursor-pointer hover:text-white" />
                    </div>
                    {threads.map(t => (
                        <div key={t.id} className="flex items-center gap-2 p-2 rounded hover:bg-gray-800 cursor-pointer text-sm text-gray-300 transition-colors">
                            <MessageSquare size={14} className="text-gray-500" />
                            {t.name}
                        </div>
                    ))}
                    {threads.length === 0 && <div className="text-xs text-gray-600 px-2 italic">No threads yet</div>}
                </div>
            )}
        </div>
    );
}
