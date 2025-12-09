.PHONY: all clean proto build-agent build-server

PROTOC_GEN_GO := $(shell which protoc-gen-go)
PROTOC_GEN_GO_GRPC := $(shell which protoc-gen-go-grpc)

all: proto build-agent build-server

proto:
	@echo "Generating Protobuf code..."
	@mkdir -p server/proto
	./tools/gen_proto.sh

build-agent:
	@echo "Building Agent..."
	cd agent && zig build

build-server:
	@echo "Building Server..."
	cd server && go build -o bin/server main.go

clean:
	rm -rf agent/zig-out agent/zig-cache
	rm -f server/bin/server

