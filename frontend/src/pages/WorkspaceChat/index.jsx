import { useState, useEffect } from 'react';
import { useHotkeys } from 'react-hotkeys-hook';
import { SmartContext } from '../../components/SmartContext';
import { PeerSelector } from '../../components/PeerSelector';
import { api } from '../../utils/api';

export default function WorkspaceChat({ workspaceId }) {
  const [threadId, setThreadId] = useState(null);
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [peerId, setPeerId] = useState(null); // Default null to force selection or load first?

  // Shortcuts
  useHotkeys('meta+enter, ctrl+enter', () => handleSend(), { enableOnFormTags: true });

  // Load threads when workspace changes
  useEffect(() => {
      if (workspaceId) {
          api.getThreads(workspaceId).then(res => {
              if (res.threads && res.threads.length > 0) {
                  setThreadId(res.threads[0].id);
              } else {
                  api.createThread(workspaceId, "General").then(t => setThreadId(t.id));
              }
          });
      } else {
          setThreadId(null);
      }
  }, [workspaceId]);

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

      const newMsgs = [...messages, { role: 'user', content: input }];
      setMessages(newMsgs);
      setInput("");

      try {
          const ctx = await api.selectContext(threadId, input);
          const res = await api.generate(peerId, newMsgs, ctx.chunks || []);
          setMessages([...newMsgs, { role: 'assistant', content: res.content || res.error || "No response" }]);
      } catch(e) {
          console.error(e);
          setMessages([...newMsgs, { role: 'system', content: "Error generating response" }]);
      }
  };

  if (!workspaceId) return <div className="flex-1 flex items-center justify-center text-gray-400">Select a workspace</div>;

  return (
    <>
      <div className="flex-1 flex flex-col min-w-0 border-r border-gray-200 h-full bg-white">
         <div className="p-4 border-b border-gray-200 bg-gray-50 flex justify-between items-center">
            <h2 className="font-semibold text-lg">Chat</h2>
            <div className="text-xs text-gray-500">Thread: {threadId ? threadId.substring(0,8) : "None"}</div>
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
