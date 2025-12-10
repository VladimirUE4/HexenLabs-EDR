package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"

	pb_command "github.com/hexenlabs/edr/server/proto/command"
	pb_service "github.com/hexenlabs/edr/server/proto/service"
)

// In a real scenario, the Admin tool would authenticate to the server via OIDC or similar.
// Here we use mTLS or just server TLS verification for simplicity to talk to the backend.

const (
	serverAddr = "localhost:50051"
	caFile     = "../../pki/certs/ca.crt"
)

func main() {
	targetAgent := flag.String("agent", "", "Target Agent ID")
	query := flag.String("osquery", "", "Osquery SQL query to execute")
	flag.Parse()

	if *targetAgent == "" || *query == "" {
		fmt.Println("Usage: admin -agent <id> -osquery <query>")
		return
	}

	fmt.Printf("Sending query '%s' to agent %s...\n", *query, *targetAgent)

	// Load CA cert to verify server
	pemServerCA, err := ioutil.ReadFile(caFile)
	if err != nil {
		log.Fatalf("Failed to load CA: %v", err)
	}
	certPool := x509.NewCertPool()
	if !certPool.AppendCertsFromPEM(pemServerCA) {
		log.Fatalf("Failed to append CA")
	}

	// Connect to Server
	creds := credentials.NewTLS(&tls.Config{
		RootCAs: certPool,
		InsecureSkipVerify: true, // For dev only if hostname doesn't match
	})
	conn, err := grpc.Dial(serverAddr, grpc.WithTransportCredentials(creds))
	if err != nil {
		log.Fatalf("Did not connect: %v", err)
	}
	defer conn.Close()

	client := pb_service.NewEDRServiceClient(conn)
	
	// Create Command Payload
	cmd := &pb_command.Command{
		CommandId: fmt.Sprintf("cmd-%d", time.Now().Unix()),
		Type: pb_command.CommandType_CMD_OSQUERY,
		Payload: &pb_command.Command_Osquery{
			Osquery: &pb_command.OsqueryCommand{
				Query: *query,
				TimeoutSeconds: 30,
			},
		},
		// Signature would be generated here with Admin Private Key
	}

	// In our current simple proto, we don't have a direct "Admin -> Server -> Agent" RPC method exposed publicly 
	// for this CLI to call directly to *push* to a specific agent immediately.
	// Usually, the Admin puts the command in a DB/Queue via an API (HTTP/REST), and the Server picks it up.
	// 
	// FOR DEMO PURPOSES: We will just print what we WOULD send.
	// Implementing the full Admin API is the next step.
	
	fmt.Printf("\n[+] Command Prepared:\nID: %s\nType: OSQUERY\nPayload: %s\n", cmd.CommandId, cmd.GetOsquery().Query)
	fmt.Println("\nTo fully implement this, we need to add an 'AdminAPI' service to the backend.")
	
	// Example of calling a hypothetical Admin RPC:
	// _, err = client.QueueCommand(ctx, &AdminQueueRequest{AgentId: *targetAgent, Command: cmd})
}

