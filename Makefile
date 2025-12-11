.PHONY: build-backend build-gateway build-agent run-backend run-gateway run-all help

# Build targets
build-backend:
	cd server && go build -o bin/backend cmd/backend/main.go

build-gateway:
	cd server && go build -o bin/gateway cmd/gateway/main.go

build-agent:
	cd agent && zig build -Doptimize=ReleaseSafe

build-all: build-backend build-gateway build-agent

# Run targets
run-backend:
	cd server && go run cmd/backend/main.go

run-gateway:
	cd server && PORT=8443 go run cmd/gateway/main.go

run-all:
	@echo "Starting Backend API and Agent Gateway..."
	@echo "Backend API: http://localhost:8080"
	@echo "Agent Gateway: http://localhost:8443"
	@trap 'kill 0' EXIT; \
	cd server && go run cmd/backend/main.go & \
	cd server && PORT=8443 go run cmd/gateway/main.go & \
	wait

# Development
dev-backend:
	cd server && go run cmd/backend/main.go

dev-gateway:
	cd server && PORT=8443 go run cmd/gateway/main.go

# Clean
clean:
	rm -rf server/bin/*
	rm -rf agent/zig-out/*

help:
	@echo "Available targets:"
	@echo "  build-backend   - Build Backend API"
	@echo "  build-gateway  - Build Agent Gateway"
	@echo "  build-agent    - Build Zig agent"
	@echo "  build-all      - Build all components"
	@echo "  run-backend    - Run Backend API (port 8080)"
	@echo "  run-gateway    - Run Agent Gateway (port 8443)"
	@echo "  run-all        - Run both services in parallel"
	@echo "  clean          - Clean build artifacts"
