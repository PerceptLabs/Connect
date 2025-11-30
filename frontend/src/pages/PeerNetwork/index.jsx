import { useState, useEffect } from 'react';
import { api } from '../../utils/api';
import { Trash2, Plus, RefreshCw, Server } from 'lucide-react';

export default function PeerNetwork() {
    const [peers, setPeers] = useState([]);
    const [isAdding, setIsAdding] = useState(false);
    const [newPeer, setNewPeer] = useState({ name: '', provider: 'ollama', base_url: 'http://localhost:11434', api_key: '', model_id: '' });
    const [availableModels, setAvailableModels] = useState([]);
    const [discovering, setDiscovering] = useState(false);
    const [status, setStatus] = useState('');

    useEffect(() => {
        loadPeers();
    }, []);

    const loadPeers = () => api.getPeers().then(setPeers);

    const handleDiscover = async () => {
        setDiscovering(true);
        setStatus("Scanning...");
        try {
            const res = await api.discoverPeer(newPeer.provider, newPeer.base_url, newPeer.api_key);
            if (res.status === 'healthy') {
                setAvailableModels(res.models);
                if (res.models.length > 0) setNewPeer({ ...newPeer, model_id: res.models[0].id });
                setStatus("Connected. Models found.");
            } else {
                setStatus("Error: " + (res.error || "Unknown error"));
            }
        } catch (e) {
            setStatus("Network error");
        } finally {
            setDiscovering(false);
        }
    };

    const handleSave = async () => {
        if (!newPeer.name || !newPeer.model_id) return;
        await api.createPeer(newPeer);
        setIsAdding(false);
        setNewPeer({ name: '', provider: 'ollama', base_url: 'http://localhost:11434', api_key: '', model_id: '' });
        setAvailableModels([]);
        setStatus('');
        loadPeers();
    };

    const handleDelete = async (id) => {
        await api.deletePeer(id);
        loadPeers();
    };

    return (
        <div className="flex-1 p-6 bg-gray-50 overflow-y-auto h-full">
            <div className="flex justify-between items-center mb-6">
                <h1 className="text-2xl font-bold text-gray-800">Peer Network</h1>
                <button onClick={() => setIsAdding(true)} className="bg-blue-600 text-white px-4 py-2 rounded flex items-center gap-2 hover:bg-blue-700 transition-colors">
                    <Plus size={18} /> Add Peer
                </button>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {peers.map(peer => (
                    <div key={peer.id} className="bg-white p-4 rounded shadow-sm border border-gray-200">
                        <div className="flex justify-between items-start mb-2">
                            <div className="flex items-center gap-2">
                                <div className="p-2 bg-blue-50 rounded text-blue-600">
                                    <Server size={18}/>
                                </div>
                                <span className="font-semibold text-gray-800">{peer.name}</span>
                            </div>
                            <button onClick={() => handleDelete(peer.id)} className="text-gray-400 hover:text-red-500 transition-colors">
                                <Trash2 size={16} />
                            </button>
                        </div>
                        <div className="text-xs text-gray-500 mb-1 font-medium">{peer.provider} • {peer.model_id}</div>
                        <div className="text-xs text-gray-400 truncate font-mono bg-gray-50 p-1 rounded mb-2">{peer.base_url}</div>
                        <div className="flex items-center gap-1 text-[10px] text-green-600 font-medium">
                            <div className="w-2 h-2 rounded-full bg-green-500"></div> Active
                        </div>
                    </div>
                ))}
                {peers.length === 0 && (
                    <div className="col-span-full text-center text-gray-400 py-10">
                        No peers configured. Add one to start collaborating.
                    </div>
                )}
            </div>

            {isAdding && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
                    <div className="bg-white p-6 rounded-lg shadow-xl w-[500px]">
                        <h2 className="text-lg font-bold mb-4">Add New Peer</h2>
                        <div className="space-y-4">
                            <div>
                                <label className="block text-xs font-semibold text-gray-500 uppercase mb-1">Name</label>
                                <input
                                    className="w-full border p-2 rounded text-sm focus:ring-1 focus:ring-blue-500 outline-none"
                                    placeholder="Display Name (e.g. Local 8B)"
                                    value={newPeer.name}
                                    onChange={e => setNewPeer({...newPeer, name: e.target.value})}
                                />
                            </div>

                            <div className="grid grid-cols-3 gap-2">
                                <div className="col-span-1">
                                    <label className="block text-xs font-semibold text-gray-500 uppercase mb-1">Provider</label>
                                    <select
                                        className="w-full border p-2 rounded text-sm bg-white focus:ring-1 focus:ring-blue-500 outline-none"
                                        value={newPeer.provider}
                                        onChange={e => setNewPeer({...newPeer, provider: e.target.value, base_url: e.target.value === 'ollama' ? 'http://localhost:11434' : 'https://api.openai.com'})}
                                    >
                                        <option value="ollama">Ollama</option>
                                        <option value="openai">OpenAI</option>
                                        <option value="lmstudio">LM Studio</option>
                                        <option value="anthropic">Anthropic</option>
                                        <option value="nanogpt">NanoGPT</option>
                                    </select>
                                </div>
                                <div className="col-span-2">
                                    <label className="block text-xs font-semibold text-gray-500 uppercase mb-1">Base URL</label>
                                    <input
                                        className="w-full border p-2 rounded text-sm focus:ring-1 focus:ring-blue-500 outline-none"
                                        placeholder="Base URL"
                                        value={newPeer.base_url}
                                        onChange={e => setNewPeer({...newPeer, base_url: e.target.value})}
                                    />
                                </div>
                            </div>

                            {newPeer.provider !== 'ollama' && (
                                <div>
                                    <label className="block text-xs font-semibold text-gray-500 uppercase mb-1">API Key</label>
                                    <input
                                        className="w-full border p-2 rounded text-sm focus:ring-1 focus:ring-blue-500 outline-none"
                                        placeholder="API Key (Stored locally)"
                                        type="password"
                                        value={newPeer.api_key}
                                        onChange={e => setNewPeer({...newPeer, api_key: e.target.value})}
                                    />
                                </div>
                            )}

                            <div className="flex items-center justify-between bg-gray-50 p-2 rounded">
                                <button onClick={handleDiscover} disabled={discovering} className="text-blue-600 text-sm flex items-center gap-1 hover:underline">
                                    <RefreshCw size={14} className={discovering ? "animate-spin" : ""} /> Test Connection & Scan
                                </button>
                                <span className={`text-xs ${status.startsWith("Error") ? "text-red-500" : "text-green-600"}`}>{status}</span>
                            </div>

                            <div>
                                <label className="block text-xs font-semibold text-gray-500 uppercase mb-1">Model</label>
                                {availableModels.length > 0 ? (
                                    <select
                                        className="w-full border p-2 rounded text-sm bg-white focus:ring-1 focus:ring-blue-500 outline-none"
                                        value={newPeer.model_id}
                                        onChange={e => setNewPeer({...newPeer, model_id: e.target.value})}
                                    >
                                        {availableModels.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                                    </select>
                                ) : (
                                    <input
                                        className="w-full border p-2 rounded text-sm focus:ring-1 focus:ring-blue-500 outline-none"
                                        placeholder="Model ID (e.g. gpt-4o)"
                                        value={newPeer.model_id}
                                        onChange={e => setNewPeer({...newPeer, model_id: e.target.value})}
                                    />
                                )}
                            </div>
                        </div>
                        <div className="flex justify-end gap-2 mt-6">
                            <button onClick={() => setIsAdding(false)} className="px-4 py-2 text-gray-600 hover:bg-gray-100 rounded text-sm">Cancel</button>
                            <button onClick={handleSave} className="px-4 py-2 bg-blue-600 text-white rounded text-sm hover:bg-blue-700">Save Peer</button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
