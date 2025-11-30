import React, { useEffect, useState } from 'react';
import DiffMatchPatch from 'diff-match-patch';

export function ConflictModal({ conflict, onResolve }) {
  if (!conflict) return null;

  const [diffHtml, setDiffHtml] = useState('');

  useEffect(() => {
    // Check if diff-match-patch loaded correctly (sometimes requires default export check)
    // In ESM, it might be named export or default.
    // We'll assume default or standard constructor.
    try {
        const dmp = new DiffMatchPatch();
        // Compare User (Local) vs AI (Remote)
        const diffs = dmp.diff_main(conflict.user_content || "", conflict.ai_content || "");
        dmp.diff_cleanupSemantic(diffs);
        setDiffHtml(dmp.diff_prettyHtml(diffs));
    } catch(e) {
        console.error("Diff failed", e);
        setDiffHtml("Error generating diff.");
    }
  }, [conflict]);

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 backdrop-blur-sm">
      <div className="bg-white dark:bg-gray-900 p-6 rounded-lg shadow-xl w-[600px] border border-gray-200 dark:border-gray-700 flex flex-col max-h-[90vh]">
        <h3 className="font-bold text-lg mb-4 text-gray-900 dark:text-gray-100 flex items-center gap-2">
            <span className="text-red-500">⚠️</span> Conflict Detected
        </h3>
        <p className="text-sm mb-4 text-gray-600 dark:text-gray-400">
          Changes detected in <span className="font-mono bg-gray-100 dark:bg-gray-800 p-1 rounded text-xs">{conflict.file_path}</span>.
        </p>

        <div className="flex-1 overflow-y-auto border rounded p-4 mb-4 bg-gray-50 dark:bg-gray-950 font-mono text-xs">
            <div dangerouslySetInnerHTML={{ __html: diffHtml }} />
        </div>

        <div className="flex gap-3 justify-end">
          <button
            onClick={() => onResolve('overwrite')}
            className="px-4 py-2 border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 rounded hover:bg-gray-100 dark:hover:bg-gray-800 text-sm"
          >
            Keep My Version
          </button>
          <button
            onClick={() => onResolve('accept')}
            className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 text-sm"
          >
            Accept Remote
          </button>
        </div>
      </div>
    </div>
  );
}
