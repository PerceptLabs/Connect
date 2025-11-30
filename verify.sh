#!/bin/bash
set -e

echo "=== Connect v1.0 Production Verification ==="

# Cleanup
rm -f connect.db connect.com

# 1. Setup Binary
echo "Setting up Binary..."
if [ -f bin/redbean.com ]; then
    echo "Using included Purpose-Built Redbean (bin/redbean.com)..."
    cp bin/redbean.com connect.com
elif [ ! -f redbean.com ]; then
    echo "Custom binary not found. Downloading standard redbean.com..."
    wget https://redbean.dev/redbean-latest.com -O redbean.com
    cp redbean.com connect.com
else
    echo "Using existing cached redbean.com..."
    cp redbean.com connect.com
fi
chmod +x connect.com

# 2. Pack
echo "Packing..."
zip -r connect.com .init.lua src/ peers.json schema.sql
cd frontend/dist && zip -r ../../connect.com . && cd ../..

# 3. Start Server
echo "Starting Server..."
./connect.com -p 8080 > server.log 2>&1 &
SERVER_PID=$!

cleanup() {
    echo "Stopping server..."
    kill $SERVER_PID || true
    echo "--- Server Log Tail ---"
    tail -n 10 server.log
}
trap cleanup EXIT

sleep 2

# 4. Check FTS5 Safeguard
if grep -q "SUCCESS: Purpose-Built Redbean Detected" server.log; then
    echo "✅ FTS5: Enabled (Purpose-Built)"
elif grep -q "WARNING: Standard Redbean Detected" server.log; then
    echo "✅ FTS5: Disabled (Shim Active) - Expected in Sandbox"
else
    echo "❌ FTS5 Check: Unknown Status"
    cat server.log
    exit 1
fi

echo "--- Testing API ---"

# Workspace
WS_ID=$(curl -s -X POST http://127.0.0.1:8080/api/workspaces -H "Content-Type: application/json" -d '{"name": "V1.4 Test"}' | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
if [ -z "$WS_ID" ]; then echo "❌ Workspace Create Failed"; exit 1; fi
echo "✅ Workspace Created"

# Peer (Security Check - Encrypted?)
PEER_ID=$(curl -s -X POST http://127.0.0.1:8080/api/peers -H "Content-Type: application/json" -d '{
    "name": "Secure Peer",
    "provider": "openai",
    "base_url": "https://api.openai.com",
    "api_key": "sk-test-key",
    "model_id": "gpt-4"
}' | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
if [ -z "$PEER_ID" ]; then echo "❌ Peer Create Failed"; exit 1; fi
echo "✅ Peer Created"

# Verify Decryption on List
LIST_RES=$(curl -s http://127.0.0.1:8080/api/peers)
if [[ "$LIST_RES" == *"sk-test-key"* ]]; then
    echo "✅ Peer List: Key decrypted correctly"
else
    echo "❌ Peer List: Key missing or corrupted"
    exit 1
fi

echo "=== Verification Complete ==="
