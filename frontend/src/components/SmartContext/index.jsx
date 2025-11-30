import { useState, useEffect } from 'react';
import { api } from '../../utils/api';

export function SmartContext({ workspaceId, threadId }) {
  const [context, setContext] = useState([]);
  const [estimate, setEstimate] = useState(null);
  const [query, setQuery] = useState('');

  useEffect(() => {
    const timer = setTimeout(() => {
        if (!threadId) return;
        api.selectContext(threadId, query).then(res => setContext(res.chunks || []));
        api.estimateContext(threadId, query).then(setEstimate);
    }, 500);
    return () => clearTimeout(timer);
  }, [threadId, query]);

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
          {estimate.warnings && estimate.warnings.map((w, i) => (
            <div key={i} className="text-red-500 text-[10px] leading-tight">{w}</div>
          ))}
        </div>
      )}

      <div className="space-y-2">
        <div className="text-xs font-semibold text-gray-400 uppercase">Relevant Chunks</div>
        {context.length === 0 && <div className="text-xs text-gray-400 italic">No relevant context found.</div>}
        {context.map((chunk, i) => (
          <div key={i} className="p-2 bg-white rounded border border-gray-200 text-xs hover:border-blue-300 transition-colors cursor-default">
            <div className="font-semibold text-gray-700 mb-1">{chunk.label || "Untitled"}</div>
            <div className="text-gray-600 truncate">{chunk.content}</div>
            <div className="text-gray-400 mt-1 flex justify-between">
                <span>Rank: {chunk.rank || "N/A"}</span>
                <span>{chunk.token_count} toks</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
