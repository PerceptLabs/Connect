import { useState, useEffect } from 'react';
import { api } from '../../utils/api';

export function PeerSelector({ selectedPeer, onSelect }) {
  const [peers, setPeers] = useState([]);

  useEffect(() => {
    api.getPeers().then(setPeers).catch(console.error);
  }, []);

  return (
    <select
        className="text-xs border border-gray-300 rounded p-1 bg-white focus:outline-none focus:border-blue-500 min-w-[120px]"
        value={selectedPeer}
        onChange={e => onSelect(e.target.value)}
    >
      {peers.map(peer => (
        <option key={peer.id} value={peer.id}>
          {peer.name}
        </option>
      ))}
    </select>
  );
}
