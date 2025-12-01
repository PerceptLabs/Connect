import React, { useState, useEffect } from 'react';
import QRCode from 'react-qr-code';
import { api } from '../utils/api';

const NetworkInfo = () => {
  const [info, setInfo] = useState(null);
  const [show, setShow] = useState(false);
  const [warning, setWarning] = useState(null);

  useEffect(() => {
    api.get('/api/network/info').then(data => {
      setInfo(data);
    }).catch(err => console.error("Network info error", err));

    api.get('/api/security/warning').then(data => {
      if (data.warning) setWarning(data.warning);
    }).catch(() => {});
  }, []);

  if (!info || info.host === '127.0.0.1' || info.host === 'localhost') {
    // Only show if network access is actually enabled or relevant?
    // The plan says "Security warning banner (only in network mode)".
    // But "Floating panel showing: Local IP...".
    // If running on localhost, might be less useful, but let's show it if user toggles it.
    // Or maybe just a small icon?
    // For now, I'll render a small trigger.
    if (!warning) return null; // If no warning (localhost mode), maybe hide by default or show small.
  }

  return (
    <div className="fixed bottom-4 right-4 z-50">
      {!show && (
        <button
          onClick={() => setShow(true)}
          className={`p-2 rounded-full shadow-lg ${warning ? 'bg-red-500 hover:bg-red-600 text-white' : 'bg-gray-800 text-white'}`}
          title="Network Info"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" />
          </svg>
        </button>
      )}

      {show && (
        <div className="bg-white dark:bg-gray-800 p-4 rounded-lg shadow-xl border border-gray-200 dark:border-gray-700 w-80">
          <div className="flex justify-between items-center mb-4">
            <h3 className="font-bold text-lg dark:text-white">Network Access</h3>
            <button onClick={() => setShow(false)} className="text-gray-500 hover:text-gray-700">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
            </button>
          </div>

          {warning && (
            <div className="bg-red-100 border-l-4 border-red-500 text-red-700 p-2 mb-4 text-sm">
              <p className="font-bold">Security Warning</p>
              <p>{warning}</p>
            </div>
          )}

          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Local Address</label>
            <div className="flex items-center">
              <input
                readOnly
                value={info?.url || ''}
                className="flex-1 bg-gray-100 dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded px-2 py-1 text-sm dark:text-white"
              />
              <button
                onClick={() => navigator.clipboard.writeText(info?.url)}
                className="ml-2 p-1 bg-blue-500 text-white rounded hover:bg-blue-600"
                title="Copy to clipboard"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M8 3a1 1 0 011-1h2a1 1 0 110 2H9a1 1 0 01-1-1z" />
                  <path d="M6 3a2 2 0 00-2 2v11a2 2 0 002 2h8a2 2 0 002-2V5a2 2 0 00-2-2 3 3 0 01-3 3H9a3 3 0 01-3-3z" />
                </svg>
              </button>
            </div>
          </div>

          <div className="flex justify-center bg-white p-2 rounded">
             {info?.url && <QRCode value={info.url} size={150} />}
          </div>
          <p className="text-center text-xs text-gray-500 mt-2">Scan to connect mobile device</p>
        </div>
      )}
    </div>
  );
};

export default NetworkInfo;
