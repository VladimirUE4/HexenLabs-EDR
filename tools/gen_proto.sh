#!/bin/bash
# Script to generate Protobuf code for Go

# Exit on error
set -e

# Ensure output directories exist
mkdir -p server/proto

# Check for protoc
if ! command -v protoc &> /dev/null; then
    echo "Error: protoc is not installed."
    exit 1
fi

echo "Generating Protobuf code..."

# Generate Go code
# We target all .proto files in subdirectories of proto/
protoc --go_out=server --go_opt=paths=source_relative \
    --go-grpc_out=server --go-grpc_opt=paths=source_relative \
    proto/*/*.proto

echo "Proto generation complete."
