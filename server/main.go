package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/hexenlabs/edr/server/api"
	"github.com/hexenlabs/edr/server/database"
)

// Server configuration
const (
	apiPort     = ":8080" // Frontend / API
	gatewayPort = ":8443" // Agent Gateway (mTLS strict)
	caFile      = "../pki/certs/ca.crt"
	certFile    = "../pki/certs/server.crt"
	keyFile     = "../pki/certs/server.key"
)

// loadTLSConfig creates a TLS config based on role
func loadTLSConfig(requireClientCert bool) (*tls.Config, error) {
	// Load Server Cert/Key
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, fmt.Errorf("failed to load key pair: %s", err)
	}

	// Load CA Cert for client verification
	caCert, err := ioutil.ReadFile(caFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read ca cert: %s", err)
	}

	caCertPool := x509.NewCertPool()
	if !caCertPool.AppendCertsFromPEM(caCert) {
		return nil, fmt.Errorf("failed to append ca cert")
	}

	// Base Config
	config := &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS13,
	}

	if requireClientCert {
		config.ClientCAs = caCertPool
		config.ClientAuth = tls.RequireAndVerifyClientCert
	} else {
		config.ClientAuth = tls.NoClientCert
	}

	return config, nil
}

func main() {
	fmt.Println("HexenLabs EDR Server Starting...")

	// 0. Initialize DB
	database.Connect()

	var wg sync.WaitGroup
	wg.Add(2)

	// 1. Start Agent Gateway (Port 8443, Strict mTLS)
	go func() {
		defer wg.Done()
		
		// Setup Gin for Gateway
		r := gin.New()
		r.Use(gin.Recovery())
		// We can add custom logger here that includes AgentID from cert
		
		api.RegisterGatewayRoutes(r)

		tlsConfig, err := loadTLSConfig(true) // TRUE = Strict mTLS
		if err != nil {
			log.Fatalf("[Gateway] Failed to load TLS: %v", err)
		}

		server := &http.Server{
			Addr:      gatewayPort,
			Handler:   r,
			TLSConfig: tlsConfig,
		}

		fmt.Printf("🔒 [Gateway] Listening on %s (Strict mTLS 1.3 enabled) - AGENTS ONLY\n", gatewayPort)
		if err := server.ListenAndServeTLS("", ""); err != nil {
			log.Fatalf("[Gateway] Failed to serve: %v", err)
		}
	}()

	// 2. Start Frontend API (Port 8080, Standard TLS)
	go func() {
		defer wg.Done()

		// Setup Gin for API
		r := gin.Default() // Default includes logger
		api.RegisterBackendRoutes(r)

		tlsConfig, err := loadTLSConfig(false) // FALSE = No Client Cert
		if err != nil {
			log.Fatalf("[API] Failed to load TLS: %v", err)
		}

		server := &http.Server{
			Addr:      apiPort,
			Handler:   r,
			TLSConfig: tlsConfig,
		}

		fmt.Printf("🌍 [API] Listening on %s (TLS enabled) - FRONTEND\n", apiPort)
		if err := server.ListenAndServeTLS("", ""); err != nil {
			log.Fatalf("[API] Failed to serve: %v", err)
		}
	}()

	wg.Wait()
}
