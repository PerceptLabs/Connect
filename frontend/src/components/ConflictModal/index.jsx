import React, { useEffect, useState } from 'react';
import { api } from '../../utils/api';

export function ConflictModal({ conflict, onResolve }) {
  if (!conflict) return null;

  const [mode, setMode] = useState('diff'); // 'diff' | 'manual'
  const [manualContent, setManualContent] = useState('');
  const [baseContent, setBaseContent] = useState('');
  const [loadingBase, setLoadingBase] = useState(false);
  const [autoMerging, setAutoMerging] = useState(false);

  const localText = conflict.user_content || "";
  const remoteText = conflict.ai_content || "";

  useEffect(() => {
      setManualContent(localText);

      // Fetch Ancestor
      if (conflict.id) {
          setLoadingBase(true);
          api.get(`/conflicts/${conflict.id}/ancestor`)
             .then(data => {
                 setBaseContent(data.content || "");
             })
             .catch(() => setBaseContent("(Base content not found)"))
             .finally(() => setLoadingBase(false));
      }
  }, [conflict, localText]);

  const handleManualResolve = () => {
      onResolve('manual', manualContent);
  };

  const handleAutoMerge = async () => {
      setAutoMerging(true);
      try {
          const res = await api.request(`/conflicts/${conflict.id}/automerge`, { method: 'POST' });
          if (res.merged) {
              setManualContent(res.merged);
              setMode('manual'); // Switch to manual to review
          }
      } catch (e) {
          console.error("Auto merge failed", e);
      } finally {
          setAutoMerging(false);
      }
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 backdrop-blur-sm p-4">
      <div className="bg-white dark:bg-gray-900 rounded-lg shadow-xl w-full max-w-[90vw] h-[85vh] border border-gray-200 dark:border-gray-700 flex flex-col">
        <div className="p-4 border-b border-gray-200 dark:border-gray-700 flex justify-between items-center">
            <h3 className="font-bold text-lg text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <span className="text-red-500">⚠️</span> Conflict: {conflict.file_path}
            </h3>
            <div className="flex gap-2">
                <button
                    onClick={() => setMode('diff')}
                    className={`px-3 py-1 rounded text-sm ${mode === 'diff' ? 'bg-blue-100 text-blue-700' : 'text-gray-600'}`}
                >
                    3-Way View
                </button>
                <button
                    onClick={() => setMode('manual')}
                    className={`px-3 py-1 rounded text-sm ${mode === 'manual' ? 'bg-blue-100 text-blue-700' : 'text-gray-600'}`}
                >
                    Merge Editor
                </button>
            </div>
        </div>

        <div className="flex-1 overflow-hidden p-4 flex gap-4">
            {mode === 'diff' ? (
                <div className="flex-1 flex gap-2 h-full">
                    {/* Local */}
                    <div className="flex-1 flex flex-col min-w-0">
                        <div className="text-xs font-semibold mb-2 text-blue-600 uppercase tracking-wide">Local (Yours)</div>
                        <textarea
                            readOnly
                            className="flex-1 w-full border rounded p-2 font-mono text-xs bg-blue-50/30 resize-none dark:bg-blue-900/10 dark:text-gray-300"
                            value={localText}
                        />
                    </div>

                    {/* Base */}
                    <div className="flex-1 flex flex-col min-w-0 border-l border-r px-2 border-gray-100 dark:border-gray-700 opacity-75">
                        <div className="text-xs font-semibold mb-2 text-gray-500 uppercase tracking-wide text-center">Base (Ancestor)</div>
                        <textarea
                            readOnly
                            className="flex-1 w-full border border-dashed rounded p-2 font-mono text-xs bg-gray-50 resize-none dark:bg-gray-800 dark:text-gray-400"
                            value={loadingBase ? "Loading..." : baseContent}
                        />
                    </div>

                    {/* Remote */}
                    <div className="flex-1 flex flex-col min-w-0">
                        <div className="text-xs font-semibold mb-2 text-purple-600 uppercase tracking-wide text-right">Remote (Incoming)</div>
                        <textarea
                            readOnly
                            className="flex-1 w-full border rounded p-2 font-mono text-xs bg-purple-50/30 resize-none dark:bg-purple-900/10 dark:text-gray-300"
                            value={remoteText}
                        />
                    </div>
                </div>
            ) : (
                <div className="flex-1 flex flex-col h-full">
                    <div className="text-sm font-semibold mb-2 text-gray-700 dark:text-gray-300 flex justify-between">
                        <span>Merge Result</span>
                        {/* Auto Merge Button inside Editor Mode? Or outside? */}
                    </div>
                    <textarea
                        className="flex-1 w-full border rounded p-2 font-mono text-xs focus:ring-2 focus:ring-blue-500 outline-none resize-none dark:bg-gray-800 dark:text-gray-200"
                        value={manualContent}
                        onChange={e => setManualContent(e.target.value)}
                    />
                </div>
            )}
        </div>

        <div className="p-4 border-t border-gray-200 dark:border-gray-700 flex justify-between items-center bg-gray-50 dark:bg-gray-800 rounded-b-lg">
           <div>
               {mode === 'diff' && (
                   <button
                        onClick={handleAutoMerge}
                        disabled={autoMerging}
                        className="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700 text-sm font-medium disabled:opacity-50"
                   >
                        {autoMerging ? "Merging..." : "✨ Auto-Merge"}
                   </button>
               )}
           </div>

          <div className="flex gap-3">
          {mode === 'manual' ? (
             <button
                onClick={handleManualResolve}
                className="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 text-sm font-medium"
             >
                Confirm Merge
             </button>
          ) : (
              <>
                <button
                    onClick={() => onResolve('overwrite')}
                    className="px-4 py-2 border border-blue-600 text-blue-600 rounded hover:bg-blue-50 text-sm font-medium"
                >
                    Keep Mine
                </button>
                <button
                    onClick={() => onResolve('accept')}
                    className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 text-sm font-medium"
                >
                    Accept Remote
                </button>
              </>
          )}
          </div>
        </div>
      </div>
    </div>
  );
}
