# HexenLabs EDR - Setup Instructions

## Agent Setup

The agent requires `osqueryd` binary to be present. Due to GitHub's 100MB file size limit, the binary is not included in this repository.

### Downloading Osquery

**For Linux (amd64):**
```bash
cd agent/assets/linux/amd64
curl -L https://pkg.osquery.io/linux/osquery-5.10.2_1.linux_x86_64.tar.gz -o osquery.tar.gz
tar xzf osquery.tar.gz
cp opt/osquery/bin/osqueryd .
rm -rf opt osquery.tar.gz
chmod +x osqueryd
```

**For Windows:**
Download from https://github.com/osquery/osquery/releases and extract `osqueryd.exe` to `agent/assets/windows/amd64/`

**For macOS:**
Download from https://github.com/osquery/osquery/releases and extract `osqueryd` to `agent/assets/macos/amd64/`

### Building the Agent

Once `osqueryd` is in place:
```bash
cd agent
zig build -Doptimize=ReleaseSafe
```

The binary will be at `zig-out/bin/hexen-agent`.


