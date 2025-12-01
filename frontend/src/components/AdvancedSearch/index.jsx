import React, { useState } from 'react';
import { api } from '../../utils/api';
import { Search } from 'lucide-react';

export default function AdvancedSearch() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [expanded, setExpanded] = useState(false);

  const handleSearch = (e) => {
      e.preventDefault();
      if (!query.trim()) return;
      setLoading(true);
      api.search(query).then(res => {
          setResults(res.results || []);
          setLoading(false);
      }).catch(err => {
          console.error(err);
          setLoading(false);
      });
  };

  return (
    <div className="relative">
       <div className={`transition-all duration-300 ${expanded ? 'w-96' : 'w-64'}`}>
           <form onSubmit={handleSearch} className="relative">
               <input
                  type="text"
                  className="w-full bg-gray-800 border border-gray-700 rounded-md py-1.5 pl-8 pr-4 text-sm text-gray-200 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                  placeholder='Search ("phrase" -exclude file:md)...'
                  value={query}
                  onChange={e => setQuery(e.target.value)}
                  onFocus={() => setExpanded(true)}
               />
               <Search size={14} className="absolute left-2.5 top-2.5 text-gray-500" />
           </form>
       </div>

       {expanded && (results.length > 0 || loading) && (
           <div className="absolute top-full left-0 w-96 mt-2 bg-white dark:bg-gray-800 rounded-md shadow-lg border border-gray-200 dark:border-gray-700 max-h-96 overflow-y-auto z-50">
               <div className="flex justify-between items-center p-2 border-b border-gray-100 dark:border-gray-700 bg-gray-50 dark:bg-gray-900">
                   <span className="text-xs font-semibold text-gray-500">Results</span>
                   <button onClick={() => { setExpanded(false); setResults([]); }} className="text-xs text-blue-500 hover:text-blue-600">Close</button>
               </div>

               {loading && <div className="p-4 text-center text-sm text-gray-500">Searching...</div>}

               {!loading && results.map((r, i) => (
                   <div key={i} className="p-3 hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer border-b border-gray-100 dark:border-gray-700 last:border-0">
                       <div className="flex justify-between mb-1">
                           <span className="text-xs font-mono bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 px-1 rounded">{r.file_path}</span>
                           <span className="text-[10px] text-gray-400">Chunk {r.chunk_id}</span>
                       </div>
                       <div className="text-sm text-gray-700 dark:text-gray-300 line-clamp-2">
                           {r.content}
                       </div>
                   </div>
               ))}

               {!loading && results.length === 0 && query && (
                   <div className="p-4 text-center text-sm text-gray-500">No results found.</div>
               )}
           </div>
       )}
    </div>
  );
}
