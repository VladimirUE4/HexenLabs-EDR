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
- **Libcurl** (dev package) for the agent

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
- **Agent Gateway** : `:8443` (Strict mTLS) - Agents only
- **Web API** : `:8080` (TLS) - Frontend only

### 3. Agent

```bash
# Download osquery (see agent/assets/README.md)
cd agent/assets/linux/amd64
curl -L https://pkg.osquery.io/linux/osquery-5.10.2_1.linux_x86_64.tar.gz -o osquery.tar.gz
tar xzf osquery.tar.gz && cp opt/osquery/bin/osqueryd . && rm -rf opt osquery.tar.gz

# Build agent (Links against libcurl)
cd ../../..
zig build -Doptimize=ReleaseSafe

# Run
./zig-out/bin/hexen-agent
```

The agent will automatically appear in the web panel.

## Usage

1. Open `http://localhost:3000` (Frontend)
2. Login (Default auth needed)
3. Click on an agent
4. Execute Osquery SQL queries (e.g., `SELECT * FROM processes;`)
5. View results in real-time

## Architecture

- **Agent** : Zig + Libcurl, self-contained (embeds osquery), mTLS communication on port 8443.
- **Server** : Go Monolith with split listeners (API vs Gateway), PostgreSQL.
- **Panel** : React/Vite.

## Security

- **mTLS 1.3 Strict** on port 8443. The server rejects any connection without a valid agent certificate signed by the CA.
- **TLS 1.3** on port 8080 for the dashboard.
- **Input validation** on server side.

## Roadmap & Technical Implementation Strategy

### Phase 1: Core Features (Current)
- ✅ Agent deployment and heartbeat
- ✅ Osquery integration
- ✅ Web administration panel
- ✅ Command execution and result retrieval
- ✅ PostgreSQL persistence
- ✅ **Secure mTLS Communication** (Zig + Libcurl)

### Phase 2: Security & Hardening 
- [ ] **Ed25519 Command Signing**: 
    *   *Implementation*: Server holds Private Key. Signs the JSON command payload. Agent holds Public Key.
    *   *Check*: Agent validates signature before passing SQL to Osquery. Prevents MITM command injection even if TLS is broken.
- [ ] **Agent Auto-update**:
    *   *Implementation*: Double-buffer mechanism. Download new binary to `.tmp`, verify signature, rename over current exe, restart via `execve` (Linux) or separate service watchdog (Windows).
- [ ] **Anti-Tampering**:
    *   *Linux*: Use `systemd` InaccessiblePaths.
    *   *Windows*: ACLs on the service and binary folder.

### Phase 3: Detection Engine 
- [ ] **Real-time Process Monitoring**:
    *   *Tech*: Don't poll. Use Osquery event tables (`process_events`) backed by Auditd (Linux) or OpenBSM (macOS).
- [ ] **File Integrity Monitoring (FIM)**:
    *   *Tech*: Osquery `file_events` (inotify/FSEvents). Alert on modification of `/etc/passwd`, `~/.ssh/authorized_keys`, etc.
- [ ] **YARA Integration**:
    *   *Tech*: Compile `libyara` in Zig.
    *   *Logic*: Scan memory of newly spawned processes (hooking via eBPF or simple periodic scan of high-risk PIDs).
- [ ] Sigma rule support
- [ ] Network connection tracking

### Phase 4: Response Capabilities 
- [ ] **Network Isolation**:
    *   *Linux*: Execute `nftables` / `iptables` rules to drop all OUTPUT except destination `SERVER_IP`.
    *   *Windows*: Use Windows Filtering Platform (WFP) API to block non-EDR traffic.
- [ ] **Process Termination**:
    *   *Tech*: Native syscall `kill` (Linux) / `TerminateProcess` (Windows).
- [ ] Automated incident response playbooks
- [ ] Network isolation

### Phase 5: Advanced Features 
- [ ] Kernel-level monitoring (eBPF on Linux, Kernel Driver on Windows, ESF on macOS)
- [ ] Memory scanning
- [ ] Threat intelligence integration
- [ ] Multi-tenant support
- [ ] Advanced analytics dashboard
- [ ] Compliance reporting