import { useState, useEffect } from 'react';
import { api } from '../../utils/api';

export function SmartContext({ workspaceId, threadId }) {
  const [context, setContext] = useState([]);
  const [estimate, setEstimate] = useState(null);
  const [query, setQuery] = useState('');
  const [pinnedDocs, setPinnedDocs] = useState([]);

  const refresh = () => {
    if (!threadId) return;
    api.selectContext(threadId, query).then(res => setContext(res.chunks || []));
    api.estimateContext(threadId, query).then(res => {
        setEstimate(res);
        if (res.pinned_documents) setPinnedDocs(res.pinned_documents);
    });
  };

  useEffect(() => {
    const timer = setTimeout(refresh, 500);
    return () => clearTimeout(timer);
  }, [threadId, query]);

  const handleTogglePin = (docId, isPinned) => {
      if (isPinned) {
          api.unpinDocument(workspaceId, docId).then(refresh);
      } else {
          api.pinDocument(workspaceId, docId).then(refresh);
      }
  };

  return (
    <div className="w-80 bg-gray-50 border-l border-gray-200 p-4 overflow-y-auto hidden md:block flex-shrink-0">
      <h3 className="font-semibold mb-4 text-sm text-gray-700 uppercase tracking-wider">Smart Context</h3>

      <div className="mb-4">
        <input
          className="w-full p-2 border border-gray-300 rounded-md text-sm focus:ring-1 focus:ring-blue-500 outline-none"
          placeholder="Search context..."
          value={query}
          onChange={e => setQuery(e.target.value)}
        />
      </div>

      {estimate && (
        <div className="mb-4 p-3 bg-white rounded-md border border-gray-200 shadow-sm">
          <div className="text-xs text-gray-500 mb-1 flex justify-between">
              <span>Token Budget</span>
              <span>{estimate.total_tokens} / 4096</span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-1.5 mb-2">
            <div
              className={`h-1.5 rounded-full ${estimate.utilization_percent > 90 ? 'bg-red-500' : 'bg-green-500'}`}
              style={{ width: `${Math.min(estimate.utilization_percent, 100)}%` }}
            />
          </div>
          <div className="text-[10px] text-gray-500 flex justify-between">
             <span>Pinned: {estimate.pinned_tokens}</span>
             <span>FTS: {estimate.fts_tokens}</span>
          </div>
          {estimate.warnings && estimate.warnings.map((w, i) => (
            <div key={i} className="text-red-500 text-[10px] leading-tight">{w}</div>
          ))}
        </div>
      )}

      {/* Pinned Documents */}
      {pinnedDocs.length > 0 && (
          <div className="mb-4">
             <div className="text-xs font-semibold text-gray-400 uppercase mb-2">Pinned Documents</div>
             {pinnedDocs.map(doc => (
                 <div key={doc.id} className="p-2 bg-blue-50 rounded border border-blue-200 text-xs mb-2 flex justify-between items-start">
                     <div>
                        <div className="font-medium text-blue-900 truncate">{doc.file_path}</div>
                        <div className="text-blue-500 text-[10px]">{doc.tokens} toks</div>
                     </div>
                     <button onClick={() => handleTogglePin(doc.document_id || doc.id, true)} className="text-blue-500 hover:text-blue-700">
                        <PinOff size={12} />
                     </button>
                 </div>
             ))}
          </div>
      )}

      <div className="space-y-2">
        <div className="text-xs font-semibold text-gray-400 uppercase">Relevant Chunks</div>
        {context.length === 0 && <div className="text-xs text-gray-400 italic">No relevant context found.</div>}
        {context.map((chunk, i) => {
            const isPinned = pinnedDocs.some(p => p.id === chunk.document_id); // Assuming chunk has document_id, which it might not in API resp
            // Actually API returns chunk.id, chunk.label, etc.
            // We need to know if the document related to this chunk is pinned.
            // But if it's pinned, it might not be in 'context' list if logic excludes pinned from search results?
            // The logic in context.lua: estimate() adds pinned tokens.
            // select() only returns FTS/Semantic chunks.
            // So these are *additional* chunks.

            return (
                <div key={i} className="p-2 bg-white rounded border border-gray-200 text-xs hover:border-blue-300 transition-colors cursor-default group relative">
                    <div className="font-semibold text-gray-700 mb-1">{chunk.label || "Untitled"}</div>
                    <div className="text-gray-600 truncate">{chunk.content}</div>
                    <div className="text-gray-400 mt-1 flex justify-between">
                        <span>Rank: {chunk.rank || "N/A"}</span>
                        <span>{chunk.token_count} toks</span>
                    </div>
                </div>
            );
        })}
      </div>
    </div>
  );
}
