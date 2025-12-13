#!/bin/bash

# Graceful shutdown function
cleanup() {
    echo "🛑 Stopping services..."
    kill $(jobs -p) 2>/dev/null
    exit
}

# Trap Ctrl+C
trap cleanup SIGINT SIGTERM

echo "🚀 Starting HexenLabs EDR..."

# 1. Compile Server
echo "📦 Compiling Server..."
cd server
go build -o bin/server main.go
if [ $? -ne 0 ]; then
    echo "❌ Server compilation failed"
    exit 1
fi
cd ..

# 2. Compile Agent
echo "📦 Compiling Agent..."
cd agent
zig build
if [ $? -ne 0 ]; then
    echo "❌ Agent compilation failed"
    exit 1
fi
cd ..

# 3. Start Server
echo "🌐 Starting Server..."
cd server
./bin/server &
SERVER_PID=$!
cd ..

# Wait for DB connection
sleep 2

# 4. Start Frontend
echo "🎨 Starting Frontend..."
cd frontend
npm run dev > /dev/null 2>&1 &
FRONT_PID=$!
cd ..

echo "✅ API Server: https://localhost:8080"
echo "✅ Agent Gateway: https://localhost:8443 (mTLS)"
echo "✅ Frontend: http://localhost:3000"
echo ""

# 5. Start Agent (Runs in foreground)
echo "🕵️  Starting Agent..."
cd agent
sudo ./zig-out/bin/hexen-agent

# Wait for background processes (if agent is backgrounded)
wait $SERVER_PID $FRONT_PID
