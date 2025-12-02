import { useState, useEffect } from 'react';
import { useHotkeys } from 'react-hotkeys-hook';
import { Brain } from 'lucide-react';
import { SmartContext } from '../../components/SmartContext';
import { PeerSelector } from '../../components/PeerSelector';
import { api } from '../../utils/api';

export default function WorkspaceChat({ workspaceId, threadId, setThreadId }) {
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [peerId, setPeerId] = useState(null); // Default null to force selection or load first?
  const [summarizing, setSummarizing] = useState(false);

  // Shortcuts
  useHotkeys('meta+enter, ctrl+enter', () => handleSend(), { enableOnFormTags: true });

  // Load messages when threadId changes
  useEffect(() => {
      if (threadId) {
          api.getMessages(threadId).then(res => {
              setMessages(res.messages || []);
          }).catch(console.error);
      } else {
          setMessages([]);
      }
  }, [threadId]);

  // Load initial peer
  useEffect(() => {
      api.getPeers().then(peers => {
          if (peers && peers.length > 0) setPeerId(peers[0].id);
      });
  }, []);

  const handleSend = async () => {
      if (!input.trim() || !threadId) return;
      if (!peerId) {
          alert("Please select a peer.");
          return;
      }

      // Optimistic update
      const tempUserMsg = { role: 'user', content: input, created_at: new Date().toISOString() };
      setMessages(prev => [...prev, tempUserMsg]);
      setInput("");

      try {
          // Persist user message
          await api.sendMessage(threadId, tempUserMsg.content, 'user');

          const ctx = await api.selectContext(threadId, tempUserMsg.content);
          const res = await api.generate(peerId, [...messages, tempUserMsg], ctx.chunks || []);

          const aiContent = res.content || res.error || "No response";

          // Persist AI message
          await api.sendMessage(threadId, aiContent, 'assistant', { peerId, model: res.model });

          setMessages(prev => [...prev, { role: 'assistant', content: aiContent, created_at: new Date().toISOString() }]);
      } catch(e) {
          console.error(e);
          setMessages(prev => [...prev, { role: 'system', content: "Error generating response" }]);
      }
  };

  if (!workspaceId) return <div className="flex-1 flex items-center justify-center text-gray-400">Select a workspace</div>;

  return (
    <>
      <div className="flex-1 flex flex-col min-w-0 border-r border-gray-200 h-full bg-white">
         <div className="p-4 border-b border-gray-200 bg-gray-50 flex justify-between items-center">
            <h2 className="font-semibold text-lg">Chat</h2>
            <div className="flex items-center gap-3">
                 <button
                    onClick={async () => {
                        if (!threadId) return;
                        setSummarizing(true);
                        try {
                            const result = await api.post('/memories/summarize', { thread_id: threadId });
                            if (result.error) {
                                alert('Error: ' + result.error);
                            } else {
                                alert('Thread summarized to project memory!');
                            }
                        } catch (e) {
                            alert('Failed to summarize');
                        }
                        setSummarizing(false);
                    }}
                    disabled={summarizing || !threadId}
                    className="text-xs px-2 py-1 bg-purple-100 text-purple-700 rounded hover:bg-purple-200 disabled:opacity-50 flex items-center gap-1 transition-colors"
                    title="Summarize decisions to memory"
                >
                    <Brain size={14} />
                    {summarizing ? 'Saving...' : 'Remember'}
                </button>
                <div className="text-xs text-gray-500">
                    {threadId ? "Active Thread" : "Select a thread"}
                </div>
            </div>
         </div>

         <div className="flex-1 overflow-y-auto p-4 space-y-4">
            {messages.length === 0 && (
                <div className="text-center text-gray-400 mt-20">Start a conversation with your peers.</div>
            )}
            {messages.map((m, i) => (
                <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                    <div className={`p-3 rounded-lg max-w-[80%] text-sm ${
                        m.role === 'user' ? 'bg-blue-600 text-white' :
                        m.role === 'system' ? 'bg-red-100 text-red-800' : 'bg-gray-100 text-gray-800'
                    }`}>
                        {m.content}
                    </div>
                </div>
            ))}
         </div>

         <div className="p-4 border-t border-gray-200 bg-white">
            <div className="flex items-center gap-2 mb-2">
                <span className="text-xs font-semibold text-gray-500 uppercase">Peer Mode</span>
                <PeerSelector selectedPeer={peerId} onSelect={setPeerId} />
            </div>
            <div className="flex gap-2">
                <textarea
                    className="flex-1 border border-gray-300 rounded-md p-2 text-sm focus:ring-2 focus:ring-blue-500 focus:outline-none resize-none"
                    rows={2}
                    placeholder="Type your message..."
                    value={input}
                    onChange={e => setInput(e.target.value)}
                    onKeyDown={e => e.key === 'Enter' && !e.shiftKey && (e.preventDefault(), handleSend())}
                />
                <button
                    onClick={handleSend}
                    className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors font-medium self-end"
                >
                    Send
                </button>
            </div>
         </div>
      </div>

      {threadId && <SmartContext workspaceId={workspaceId} threadId={threadId} />}
    </>
  );
}
