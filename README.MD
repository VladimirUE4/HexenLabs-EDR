
<div align="center">
  <img src="https://avatars.githubusercontent.com/u/248723226?s=200&v=4" alt="HexenLabs Logo" width="200"/>
</div>

# HexenLabs EDR

Multi-platform EDR/XDR (Windows, Linux, macOS) with Zig agent and web administration panel.

## Prerequisites

- **Zig** 0.15+ (for agent)
- **Go** 1.21+ (for server)
- **PostgreSQL** 15+ (or Docker)
- **Protobuf Compiler** (`protoc`)

## Quick Setup

### 1. Database

```bash
# Option A: Docker
docker run --name postgres-edr -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=hexen_edr -p 5432:5432 -d postgres:15

# Option B: Local PostgreSQL
createdb hexen_edr
```

### 2. Server (Backend API + Agent Gateway)

```bash
cd server
go mod download

# Option A: Using Makefile (recommended)
make run-all

# Option B: Manual (2 terminals)
# Terminal 1: Backend API
go run cmd/backend/main.go

# Terminal 2: Agent Gateway
PORT=8443 go run cmd/gateway/main.go
```

Servers start on:
- **Backend API** : `http://localhost:8080/api` (Frontend)
- **Agent Gateway** : `http://localhost:8443/api` (Agents)

### 3. Frontend (React)

```bash
cd frontend
npm install
npm run dev
```

Frontend runs on `http://localhost:3000` and proxies API requests to the server.

### 4. Agent

```bash
# Download osquery (see agent/assets/README.md)
cd agent/assets/linux/amd64
curl -L https://pkg.osquery.io/linux/osquery-5.10.2_1.linux_x86_64.tar.gz -o osquery.tar.gz
tar xzf osquery.tar.gz && cp opt/osquery/bin/osqueryd . && rm -rf opt osquery.tar.gz

# Build agent
cd ../../..
zig build -Doptimize=ReleaseSafe

# Run
./zig-out/bin/hexen-agent
```

The agent will automatically appear in the web panel.

## Usage

1. Start both servers (`make run-all` in root directory, or manually in 2 terminals)
2. Start the frontend (`npm run dev` in `frontend/` directory)
3. Open `http://localhost:3000` in your browser
4. Login with `admin` / `admin` (change in production!)
5. Click on an agent
6. Execute Osquery SQL queries (e.g., `SELECT * FROM processes;`)
7. View results in real-time

**Note**: Agents must be configured to connect to port **8443** (Agent Gateway), not 8080.

## Architecture

- **Agent** : Zig, self-contained (embeds osquery), HTTP communication (port 8443)
- **Backend API** : Go, REST API for frontend (port 8080), JWT auth
- **Agent Gateway** : Go, REST API for agents (port 8443), mTLS (to be implemented)
- **Frontend** : React + TypeScript + Vite
- **Database** : PostgreSQL (shared)

## Security

- mTLS 1.3 for Agent ↔ Server (certificates in `pki/`)
- Signed commands (Ed25519) - To be implemented
- Input validation on server side

## Development

```bash
# Generate Protobuf
./tools/gen_proto.sh

# Build everything
make build-agent build-server
```



## Roadmap

### Phase 1: base Features (Current)
- ✅ Agent deployment and heartbeat
- ✅ Osquery integration
- ✅ Web administration panel
- ✅ Command execution and result retrieval
- ✅ PostgreSQL persistence

### Phase 2: Security & Hardening 
- [ ] mTLS
- [ ] Ed25519 command signing
- [ ] Agent auto-update mechanism (hot reload)
- [ ] Self-protection (prevent agent termination)
- [ ] Certificate rotation automation
- [ ] Audit logging (immutable)
- [ ] Incident Response Team
- [ ] Quarantine
- [ ] YARA rule engine integration
- [ ] Sigma rule support

### Phase 3: Detection Engine 
- [ ] Real-time process monitoring
- [ ] Network connection tracking
- [ ] File integrity monitoring (FIM)
- [ ] Forensics
- [ ] Behavioral detection (ML-based)

### Phase 4: Response Capabilities 
- [ ] Process termination
- [ ] Network isolation
- [ ] File quarantine
- [ ] Registry monitoring (Windows)
- [ ] Automated incident response playbooks

### Phase 5: Advanced Features 
- [ ] Kernel-level monitoring (eBPF on Linux, Kernel Driver on Windows, ESF on macOS) NOT POSSIBLE WITH ZIG FOR NOW ?
- [ ] Memory scanning
- [ ] Threat intelligence integration
- [ ] Multi-tenant support
- [ ] Advanced analytics dashboard
- [ ] Compliance reporting
