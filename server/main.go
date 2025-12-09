package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"

	pb_common "github.com/hexenlabs/edr/server/proto/common"
	pb_service "github.com/hexenlabs/edr/server/proto/service"
	pb_telemetry "github.com/hexenlabs/edr/server/proto/telemetry"
	// pb_command "github.com/hexenlabs/edr/server/proto/command"
)

// Server configuration
const (
	port = ":50051"
	certFile = "../pki/certs/server.crt"
	keyFile  = "../pki/certs/server.key"
)

// server implements the EDRServiceServer interface
type server struct {
	pb_service.UnimplementedEDRServiceServer
}

// Heartbeat implementation
func (s *server) Heartbeat(ctx context.Context, agent *pb_common.AgentIdentity) (*pb_common.StatusResponse, error) {
	log.Printf("Received Heartbeat from Agent: %s (OS: %s)", agent.AgentId, agent.OsType)
	return &pb_common.StatusResponse{
		Status: pb_common.Status_STATUS_SUCCESS,
		Message: "Heartbeat acknowledged",
	}, nil
}

// StreamTelemetry implementation
func (s *server) StreamTelemetry(stream pb_service.EDRService_StreamTelemetryServer) error {
	for {
		batch, err := stream.Recv()
		if err == io.EOF {
			// Finished receiving
			return stream.SendAndClose(&pb_common.StatusResponse{
				Status: pb_common.Status_STATUS_SUCCESS,
				Message: "Telemetry batch processed",
			})
		}
		if err != nil {
			log.Printf("Error receiving telemetry: %v", err)
			return err
		}

		// Process batch
		log.Printf("Received %d events from agent %s", len(batch.Events), batch.Agent.AgentId)
		for _, event := range batch.Events {
			// Simplified processing
			switch e := event.Event.(type) {
			case *pb_telemetry.TelemetryEvent_ProcessExec:
				log.Printf("[PROCESS] %s (PID: %d)", e.ProcessExec.ImagePath, e.ProcessExec.Pid)
			case *pb_telemetry.TelemetryEvent_NetworkConn:
				log.Printf("[NET] %s -> %s:%d", e.NetworkConn.LocalAddress, e.NetworkConn.RemoteAddress, e.NetworkConn.RemotePort)
			}
		}
	}
}

// CommandChannel implementation
func (s *server) CommandChannel(stream pb_service.EDRService_CommandChannelServer) error {
	// In a real implementation, this would handle a channel to push commands.
	// For now, just listen for responses.
	for {
		resp, err := stream.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		log.Printf("[CMD RESPONSE] ID: %s, Status: %s, Output: %s", resp.CommandId, resp.Status, resp.Output)
	}
}

func main() {
	fmt.Println("HexenLabs EDR Server Starting...")

	// 1. Setup mTLS credentials
	creds, err := credentials.NewServerTLSFromFile(certFile, keyFile)
	if err != nil {
		log.Fatalf("Failed to load TLS keys: %v", err)
	}

	// 2. Start TCP Listener
	lis, err := net.Listen("tcp", port)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	fmt.Printf("Listening on %s (mTLS enabled)\n", port)

	// 3. Create gRPC Server with TLS
	s := grpc.NewServer(grpc.Creds(creds))

	// 4. Register Services
	pb_service.RegisterEDRServiceServer(s, &server{})

	// 5. Serve
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
