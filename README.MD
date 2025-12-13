
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

### 2. Server (Backend + Web Panel)

```bash
cd server
go mod download
go build -o bin/server main.go

# Configure DB connection in main.go if needed (DSN)
./bin/server
```

Server starts on:
- **gRPC** : `:50051` (mTLS)
- **Web Panel** : `http://localhost:8080`

### 3. Agent

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

1. Open `http://localhost:8080`
2. Click on an agent
3. Execute Osquery SQL queries (e.g., `SELECT * FROM processes;`)
4. View results in real-time

## Architecture

- **Agent** : Zig, self-contained (embeds osquery), HTTP communication
- **Server** : Go, gRPC + REST API, PostgreSQL
- **Panel** : Vanilla HTML/JS (Bootstrap)

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

### Phase 1: Core Features (Current)
- ✅ Agent deployment and heartbeat
- ✅ Osquery integration
- ✅ Web administration panel
- ✅ Command execution and result retrieval
- ✅ PostgreSQL persistence

### Phase 2: Security & Hardening 
- [ ] Ed25519 command signing
- [ ] Agent auto-update mechanism (hot reload)
- [ ] Self-protection (prevent agent termination)
- [ ] Certificate rotation automation
- [ ] Audit logging (immutable)

### Phase 3: Detection Engine 
- [ ] Real-time process monitoring
- [ ] Network connection tracking
- [ ] File integrity monitoring (FIM)
- [ ] YARA rule engine integration
- [ ] Sigma rule support
- [ ] Behavioral detection (ML-based)

### Phase 4: Response Capabilities 
- [ ] Process termination
- [ ] Network isolation
- [ ] File quarantine
- [ ] Registry monitoring (Windows)
- [ ] Automated incident response playbooks

### Phase 5: Advanced Features 
- [ ] Kernel-level monitoring (eBPF on Linux, Kernel Driver on Windows, ESF on macOS)
- [ ] Memory scanning
- [ ] Threat intelligence integration
- [ ] Multi-tenant support
- [ ] Advanced analytics dashboard
- [ ] Compliance reporting
