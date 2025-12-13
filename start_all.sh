#!/bin/bash

# Fonction pour tout arrêter proprement
cleanup() {
    echo "🛑 Arrêt des services..."
    kill $(jobs -p) 2>/dev/null
    exit
}

# Intercepter Ctrl+C
trap cleanup SIGINT SIGTERM

echo "🚀 Démarrage de HexenLabs EDR..."

# 1. Compilation du serveur
echo "📦 Compilation du serveur..."
cd server
go build -o bin/server main.go
if [ $? -ne 0 ]; then
    echo "❌ Erreur de compilation du serveur"
    exit 1
fi
cd ..

# 2. Compilation de l'agent
echo "📦 Compilation de l'agent..."
cd agent
zig build
if [ $? -ne 0 ]; then
    echo "❌ Erreur de compilation de l'agent"
    exit 1
fi
cd ..

# 3. Lancement du serveur
echo "🌐 Lancement du serveur..."
cd server
./bin/server &
SERVER_PID=$!
cd ..

# Attendre que le serveur démarre
sleep 2

# 4. Lancement du frontend
echo "🎨 Lancement du frontend..."
cd frontend
npm run dev > /dev/null 2>&1 &
FRONT_PID=$!
cd ..

echo "✅ Serveur API: https://localhost:8080"
echo "✅ Gateway Agents: https://localhost:8443 (mTLS)"
echo "✅ Frontend: http://localhost:3000"
echo ""

# 5. Lancement de l'agent (optionnel, décommenter pour lancer automatiquement)
echo "🕵️  Lancement de l'agent..."
cd agent
./zig-out/bin/hexen-agent
# Si vous voulez lancer plusieurs agents ou tester manuellement, commentez la ligne ci-dessus

# Attendre la fin des processus
wait $SERVER_PID $FRONT_PID
