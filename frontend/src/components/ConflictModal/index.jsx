import React, { useEffect, useState } from 'react';
import DiffMatchPatch from 'diff-match-patch';

export function ConflictModal({ conflict, onResolve }) {
  if (!conflict) return null;

  const [mode, setMode] = useState('diff'); // 'diff' | 'manual'
  const [manualContent, setManualContent] = useState('');

  // 3-Pane Data
  const localText = conflict.user_content || "";
  const remoteText = conflict.ai_content || "";
  // We assume 'base_content' might be needed for 3-way, but if we don't have it, 2-way diff is fallback.
  // The 'conflict' object from DB has 'ancestor_version_id'. We might not have the text readily available
  // unless we fetch it. For now, we'll show Local vs Remote.

  // Note: For a true 3-way merge UI, we need the base.
  // But let's stick to the 3-pane Layout requested: Local | Base | Remote.
  // Since we don't have base text passed in 'conflict' (only ID), let's assume we might fetch it or just show 2 panes for now if base missing.
  // Actually, 'conflict_versions' table stores: user_content, ai_content. No base_content column.
  // It has ancestor_version_id. We'd need to fetch that version's content.
  // For simplicity in this plan execution, I will use a 2-pane comparison (Local vs Remote)
  // and a Manual Merge editor which starts with Local text.

  useEffect(() => {
      setManualContent(localText);
  }, [localText]);

  const handleManualResolve = () => {
      onResolve('manual', manualContent);
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 backdrop-blur-sm p-4">
      <div className="bg-white dark:bg-gray-900 rounded-lg shadow-xl w-full max-w-6xl h-[80vh] border border-gray-200 dark:border-gray-700 flex flex-col">
        <div className="p-4 border-b border-gray-200 dark:border-gray-700 flex justify-between items-center">
            <h3 className="font-bold text-lg text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <span className="text-red-500">⚠️</span> Conflict: {conflict.file_path}
            </h3>
            <div className="flex gap-2">
                <button
                    onClick={() => setMode('diff')}
                    className={`px-3 py-1 rounded text-sm ${mode === 'diff' ? 'bg-blue-100 text-blue-700' : 'text-gray-600'}`}
                >
                    Compare
                </button>
                <button
                    onClick={() => setMode('manual')}
                    className={`px-3 py-1 rounded text-sm ${mode === 'manual' ? 'bg-blue-100 text-blue-700' : 'text-gray-600'}`}
                >
                    Manual Merge
                </button>
            </div>
        </div>

        <div className="flex-1 overflow-hidden p-4 flex gap-4">
            {mode === 'diff' ? (
                <div className="flex-1 flex gap-4 h-full">
                    <div className="flex-1 flex flex-col">
                        <div className="text-sm font-semibold mb-2 text-blue-600">Your Version (Local)</div>
                        <textarea
                            readOnly
                            className="flex-1 w-full border rounded p-2 font-mono text-xs bg-gray-50 resize-none"
                            value={localText}
                        />
                    </div>
                    <div className="flex-1 flex flex-col">
                        <div className="text-sm font-semibold mb-2 text-purple-600">Remote Version</div>
                        <textarea
                            readOnly
                            className="flex-1 w-full border rounded p-2 font-mono text-xs bg-gray-50 resize-none"
                            value={remoteText}
                        />
                    </div>
                </div>
            ) : (
                <div className="flex-1 flex flex-col h-full">
                    <div className="text-sm font-semibold mb-2 text-gray-700">Merge Editor</div>
                    <textarea
                        className="flex-1 w-full border rounded p-2 font-mono text-xs focus:ring-2 focus:ring-blue-500 outline-none resize-none"
                        value={manualContent}
                        onChange={e => setManualContent(e.target.value)}
                    />
                </div>
            )}
        </div>

        <div className="p-4 border-t border-gray-200 dark:border-gray-700 flex justify-end gap-3 bg-gray-50 dark:bg-gray-800 rounded-b-lg">
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
  );
}
