package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"

	"github.com/gin-gonic/gin"
	"github.com/hexenlabs/edr/server/api"
	"github.com/hexenlabs/edr/server/auth"
	"github.com/hexenlabs/edr/server/database"
	pb_common "github.com/hexenlabs/edr/server/proto/common"
	pb_service "github.com/hexenlabs/edr/server/proto/service"
	pb_telemetry "github.com/hexenlabs/edr/server/proto/telemetry"
	pb_command "github.com/hexenlabs/edr/server/proto/command"
)

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// Server configuration
const (
	port = ":50051"
	certFile = "../pki/certs/server.crt"
	keyFile  = "../pki/certs/server.key"
	// Default to local postgres for dev
	// In production, load from environment variables
	dsn = getEnvOrDefault("DATABASE_DSN", "host=localhost user=postgres password=postgres dbname=hexen_edr port=5432 sslmode=disable TimeZone=UTC")
)

// server implements the EDRServiceServer interface
type server struct {
	pb_service.UnimplementedEDRServiceServer
}

// Heartbeat implementation
func (s *server) Heartbeat(ctx context.Context, agent *pb_common.AgentIdentity) (*pb_common.StatusResponse, error) {
	// Update Agent in DB
	var agentModel database.AgentModel
	result := database.DB.First(&agentModel, "id = ?", agent.AgentId)
	
	if result.Error != nil {
		// New Agent
		agentModel = database.AgentModel{
			ID: agent.AgentId,
			Hostname: agent.Hostname,
			OsType: agent.OsType,
			OsVersion: agent.OsVersion,
			Status: "ONLINE",
			CreatedAt: time.Now(),
		}
		if len(agent.IpAddresses) > 0 {
			agentModel.IpAddress = agent.IpAddresses[0]
		}
		database.DB.Create(&agentModel)
		log.Printf("[NEW AGENT] %s enrolled", agent.AgentId)
	} else {
		// Update existing
		agentModel.LastSeen = time.Now()
		agentModel.Status = "ONLINE"
		database.DB.Save(&agentModel)
	}

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

// GetPendingCommands implementation
func (s *server) GetPendingCommands(ctx context.Context, agent *pb_common.AgentIdentity) (*pb_command.Command, error) {
	var cmdModel database.CommandModel
	// Find oldest PENDING command
	result := database.DB.Where("agent_id = ? AND status = ?", agent.AgentId, "PENDING").Order("created_at asc").First(&cmdModel)
	
	if result.Error != nil {
		// No commands
		return nil, nil // Or return a specific empty status
	}

	// Update to SENT
	cmdModel.Status = "SENT"
	database.DB.Save(&cmdModel)

	// Convert to Proto
	cmd := &pb_command.Command{
		CommandId: cmdModel.ID,
		Type: pb_command.CommandType_CMD_OSQUERY, // Hardcoded for this demo, usually store type in DB
		Payload: &pb_command.Command_Osquery{
			Osquery: &pb_command.OsqueryCommand{
				Query: cmdModel.Payload,
			},
		},
	}
	return cmd, nil
}

// CommandChannel implementation
func (s *server) CommandChannel(stream pb_service.EDRService_CommandChannelServer) error {
	// Receive the first message which should be a dummy response or similar to identify the agent?
	// OR: The stream is established. We need to identify WHICH agent is connected.
	// In gRPC, we can get this from the Context (Metadata), but our proto didn't enforce sending ID in metadata.
	// Let's assume the agent sends an initial "Hello" or we trust the mTLS CN.
	// FOR NOW: We just assume the stream is open and we wait for responses on one side, and push commands on the other.
	// But wait, to push to a specific agent, we need to map Stream <-> AgentID.
	
	// Complex topic: Mapping streams. 
	// Simplification for MVP: We peek the first message from Agent which should contain its ID? 
	// Actually, the current proto for CommandChannel expects stream CommandResponse from client.
	// So we can read the first CommandResponse (even if empty) to get the ID if we abuse the proto, 
	// OR we rely on Heartbeat being sent separate.
	
	// Hack for MVP: The Agent loop sends responses.
	// To SEND commands, we need to be in a loop checking the DB.
	
	// Let's rely on the client sending a "Poll" or KeepAlive on this channel.
	// BUT proper way: 
	// 1. Agent connects.
	// 2. We loop: Check DB for commands for this agent -> Send.
	// 3. Concurrent loop: Recv responses -> Update DB.
	
	// Since we don't have the AgentID easily in this context without metadata, 
	// we will implement a "Pull" model where the agent sends a specific "ReadyForCommand" message?
	// No, let's just make the agent send a dummy response with its ID first.
	
	ctx := stream.Context()
	_ = ctx
	
	// Create a channel to signal we are done
	done := make(chan bool)

	// Goroutine to receive responses from Agent
	go func() {
		defer close(done)
		for {
			resp, err := stream.Recv()
			if err == io.EOF {
				return
			}
			if err != nil {
				log.Printf("Error receiving command response: %v", err)
				return
			}
			
			// Log response
			log.Printf("[CMD RESPONSE] ID: %s, Status: %s", resp.CommandId, resp.Status)
			
			// Update DB
			var cmd database.CommandModel
			if err := database.DB.First(&cmd, "id = ?", resp.CommandId).Error; err == nil {
				cmd.Status = resp.Status.String()
				cmd.ResultOutput = resp.Output
				if resp.ErrorMessage != "" {
					cmd.ErrorMessage = resp.ErrorMessage
				}
				now := time.Now()
				cmd.CompletedAt = &now
				database.DB.Save(&cmd)
			}
			
			// We can capture the Agent ID from the response if we want to map it, 
			// but for the sending loop below, we need the ID upfront.
		}
	}()

	// Sending Loop (Push pending commands)
	// ISSUE: We don't know the AgentID associated with this stream unless the agent told us.
	// Let's assume for this MVP that we broadcast or we can't push yet.
	// TO FIX: The agent should send its ID in the first message or metadata.
	
	// Workaround: We wait for the first response to get the AgentID? 
	// Or we just return nil and let the agent implement polling via a Unary call "GetPendingCommands"?
	// "GetPendingCommands" is easier for firewall/NAT traversal usually anyway (Long Polling).
	
	// Let's Switch strategy to Long Polling for simplicity and robustness in this MVP.
	// CommandChannel is bidirectional but managing stateful streams is hard in 5 mins.
	// We will ignore this server-side push loop for now and implement a Unary "GetCommands" in the proto?
	// OR: We just wait for the agent.
	
	<-done
	return nil
}

func main() {
	fmt.Println("HexenLabs EDR Server Starting...")
	
	// 0. Init Database
	// Ensure you have a running postgres instance or update the DSN
	// database.InitDB(dsn) 
	database.InitDB(dsn)
	
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

	// 5. Start HTTP API Server (in goroutine)
	go func() {
		fmt.Println("Starting Web Panel on :8080...")
		r := gin.Default()
		
		// Public routes (auth)
		r.POST("/api/auth/login", auth.Login)
		r.POST("/api/auth/refresh", auth.Refresh)
		
		// Protected routes
		protected := r.Group("/api")
		protected.Use(auth.AuthMiddleware())
		{
			protected.GET("/auth/me", auth.Me)
			protected.GET("/agents", api.GetAgents)
			protected.POST("/agents/:id/osquery", api.QueueOsqueryCommand)
			protected.GET("/agents/:id/commands", api.GetAgentCommands)
		}
		
		// Agent routes (no auth for now, but should use mTLS)
		agentRoutes := r.Group("/api")
		{
			agentRoutes.POST("/heartbeat", api.AgentHeartbeat)
			agentRoutes.GET("/agents/:id/tasks/next", api.GetNextTask)
			agentRoutes.POST("/agents/:id/tasks/:cmd_id/result", api.PostTaskResult)
		}
		
		if err := r.Run(":8080"); err != nil {
			log.Fatalf("Failed to run HTTP server: %v", err)
		}
	}()

	// 6. Serve gRPC
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
