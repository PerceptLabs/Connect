import React, { useState } from 'react';
import { api } from '../utils/api';

export function LoginModal({ onSuccess }) {
  const [password, setPassword] = useState('');
  const [recovery, setRecovery] = useState('');
  const [isRecovery, setIsRecovery] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      // Direct fetch to avoid 401 interceptor loop if we used api.js wrapper improperly
      // But api.js doesn't handle login logic yet.
      // We'll use fetch directly for auth.
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(
          isRecovery ? { recovery_token: recovery } : { password: password }
        )
      });

      const data = await res.json();
      if (res.ok && data.token) {
        // Set token
        api.setToken(data.token);
        // Persist?
        sessionStorage.setItem('connect_auth', data.token);
        onSuccess();
      } else {
        setError(data.error || "Login failed");
      }
    } catch (err) {
      setError("Network error");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/80 flex items-center justify-center z-[100] backdrop-blur-md">
      <div className="bg-white dark:bg-gray-900 rounded-xl shadow-2xl w-full max-w-md p-8 border border-gray-200 dark:border-gray-700">
        <div className="text-center mb-6">
          <div className="mx-auto w-12 h-12 bg-blue-600 rounded-lg flex items-center justify-center mb-4">
             <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"></path></svg>
          </div>
          <h2 className="text-2xl font-bold text-gray-900 dark:text-white">Connect Login</h2>
          <p className="text-gray-500 dark:text-gray-400 mt-2 text-sm">
            {isRecovery ? "Enter your recovery token" : "Enter your password"}
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="p-3 bg-red-50 dark:bg-red-900/30 text-red-600 dark:text-red-400 text-sm rounded-lg border border-red-100 dark:border-red-900/50">
              {error}
            </div>
          )}

          {isRecovery ? (
            <div>
              <input
                type="text"
                value={recovery}
                onChange={(e) => setRecovery(e.target.value)}
                placeholder="Recovery Token"
                className="w-full px-4 py-2 border rounded-lg dark:bg-gray-800 dark:border-gray-700 dark:text-white focus:ring-2 focus:ring-blue-500 outline-none transition-all"
                autoFocus
              />
            </div>
          ) : (
             <div>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Password"
                className="w-full px-4 py-2 border rounded-lg dark:bg-gray-800 dark:border-gray-700 dark:text-white focus:ring-2 focus:ring-blue-500 outline-none transition-all"
                autoFocus
              />
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full py-2 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors flex justify-center items-center"
          >
            {loading ? (
                <svg className="animate-spin h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>
            ) : (
                isRecovery ? "Recover Access" : "Sign In"
            )}
          </button>
        </form>

        <div className="mt-6 text-center text-sm">
             <button
                onClick={() => { setIsRecovery(!isRecovery); setError(''); }}
                className="text-gray-500 hover:text-gray-800 dark:hover:text-gray-200 underline"
             >
                {isRecovery ? "Back to Password Login" : "Use Recovery Token"}
             </button>
        </div>
      </div>
    </div>
  );
}
