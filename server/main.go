package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net"
	"net/http"

	"github.com/gin-gonic/gin"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"

	"github.com/hexenlabs/edr/server/api"
	"github.com/hexenlabs/edr/server/database"
	pb_common "github.com/hexenlabs/edr/server/proto/common"
	pb_service "github.com/hexenlabs/edr/server/proto/service"
)

// Server configuration
const (
	grpcPort = ":50051"
	httpPort = ":8080"
	caFile   = "../../pki/certs/ca.crt"
	certFile = "../../pki/certs/server.crt"
	keyFile  = "../../pki/certs/server.key"
)

// server implements the EDRServiceServer interface
type server struct {
	pb_service.UnimplementedEDRServiceServer
}

// Heartbeat implementation
func (s *server) Heartbeat(ctx context.Context, agent *pb_common.AgentIdentity) (*pb_common.StatusResponse, error) {
	log.Printf("Received Heartbeat from Agent: %s (OS: %s)", agent.AgentId, agent.OsType)
	return &pb_common.StatusResponse{
		Status:  pb_common.Status_STATUS_SUCCESS,
		Message: "Heartbeat acknowledged",
	}, nil
}

// StreamTelemetry implementation
func (s *server) StreamTelemetry(stream pb_service.EDRService_StreamTelemetryServer) error {
	for {
		batch, err := stream.Recv()
		if err == io.EOF {
			return stream.SendAndClose(&pb_common.StatusResponse{
				Status:  pb_common.Status_STATUS_SUCCESS,
				Message: "Telemetry batch processed",
			})
		}
		if err != nil {
			log.Printf("Error receiving telemetry: %v", err)
			return err
		}

		log.Printf("Received %d events from agent %s", len(batch.Events), batch.Agent.AgentId)
	}
}

// CommandChannel implementation
func (s *server) CommandChannel(stream pb_service.EDRService_CommandChannelServer) error {
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

func loadTLSCredentials() (*tls.Config, error) {
	// Load Server Cert/Key
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, fmt.Errorf("failed to load key pair: %s", err)
	}

	// Load CA Cert
	caCert, err := ioutil.ReadFile(caFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read ca cert: %s", err)
	}

	caCertPool := x509.NewCertPool()
	if !caCertPool.AppendCertsFromPEM(caCert) {
		return nil, fmt.Errorf("failed to append ca cert")
	}

	// Create TLS Config with mTLS
	config := &tls.Config{
		Certificates: []tls.Certificate{cert},
		ClientCAs:    caCertPool,
		ClientAuth:   tls.RequireAndVerifyClientCert,
		MinVersion:   tls.VersionTLS13,
	}

	return config, nil
}

func loadTLSCredentialsForFrontend() (*tls.Config, error) {
	// Load Server Cert/Key
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, fmt.Errorf("failed to load key pair: %s", err)
	}

	// Create TLS Config for frontend (no client cert required)
	config := &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS13,
		ClientAuth:   tls.NoClientCert, // Explicitly disable client cert requirement
	}

	return config, nil
}

func main() {
	fmt.Println("HexenLabs EDR Server Starting...")

	// 0. Initialize DB
	database.Connect()


	// 1. Load mTLS Config
	tlsConfig, err := loadTLSCredentials()
	if err != nil {
		log.Fatalf("Failed to load TLS credentials: %v", err)
	}

	// 2. Start gRPC Server (Goroutine)
	go func() {
		lis, err := net.Listen("tcp", grpcPort)
		if err != nil {
			log.Fatalf("failed to listen: %v", err)
		}

		// gRPC specific credentials
		creds := credentials.NewTLS(tlsConfig)
		s := grpc.NewServer(grpc.Creds(creds))
		pb_service.RegisterEDRServiceServer(s, &server{})

		fmt.Printf("gRPC Listening on %s (mTLS enabled)\n", grpcPort)
		if err := s.Serve(lis); err != nil {
			log.Fatalf("failed to serve gRPC: %v", err)
		}
	}()

	// 3. Start HTTP API Server (Main Thread)
	// Setup Gin
	r := gin.Default()
	api.RegisterBackendRoutes(r)
	api.RegisterGatewayRoutes(r)

	// Use TLS config without client cert requirement for frontend
	frontendTLSConfig, err := loadTLSCredentialsForFrontend()
	if err != nil {
		log.Fatalf("Failed to load frontend TLS credentials: %v", err)
	}

	server := &http.Server{
		Addr:      httpPort,
		Handler:   r,
		TLSConfig: frontendTLSConfig,
	}

	fmt.Printf("HTTP API Listening on %s (TLS enabled, no client cert for frontend)\n", httpPort)
	if err := server.ListenAndServeTLS("", ""); err != nil {
		log.Fatalf("failed to serve HTTP: %v", err)
	}
}
