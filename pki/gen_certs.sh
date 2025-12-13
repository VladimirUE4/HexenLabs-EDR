#!/bin/bash

# Exit on error
set -e

mkdir -p certs
cd certs

echo "Generating CA..."
# 1. Generate CA Private Key
openssl genpkey -algorithm Ed25519 -out ca.key

# 2. Generate CA Certificate
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt -subj "/C=FR/ST=Paris/L=Paris/O=HexenLabs/OU=Security/CN=HexenLabs Root CA"

echo "Generating Server Certificate..."
# 3. Generate Server Private Key
openssl genpkey -algorithm Ed25519 -out server.key

# 4. Generate Server CSR (Certificate Signing Request)
# Note: For real use, SubjectAltName (SAN) is required for modern TLS
openssl req -new -key server.key -out server.csr -subj "/C=FR/ST=Paris/L=Paris/O=HexenLabs/OU=Server/CN=localhost" -config <(cat /etc/ssl/openssl.cnf <(printf "\n[SAN]\nsubjectAltName=DNS:localhost,IP:127.0.0.1")) -reqexts SAN

# 5. Sign Server CSR with CA
openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key -set_serial 01 -out server.crt -extensions SAN -extfile <(cat /etc/ssl/openssl.cnf <(printf "\n[SAN]\nsubjectAltName=DNS:localhost,IP:127.0.0.1"))

echo "Generating Agent Certificate..."
# 6. Generate Agent Private Key
openssl genpkey -algorithm Ed25519 -out agent.key

# 7. Generate Agent CSR
openssl req -new -key agent.key -out agent.csr -subj "/C=FR/ST=Paris/L=Paris/O=HexenLabs/OU=Agent/CN=agent-001"

# 8. Sign Agent CSR with CA
openssl x509 -req -days 365 -in agent.csr -CA ca.crt -CAkey ca.key -set_serial 02 -out agent.crt

echo "Done. Certificates are in pki/certs/"
ls -l

