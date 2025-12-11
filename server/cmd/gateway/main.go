package main

import (
	"fmt"
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/hexenlabs/edr/server/api"
	"github.com/hexenlabs/edr/server/database"
)

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	fmt.Println("HexenLabs EDR Agent Gateway Starting...")

	// 1. Init Database
	dsn := getEnvOrDefault("DATABASE_DSN", "host=localhost user=postgres password=postgres dbname=hexen_edr port=5432 sslmode=disable TimeZone=UTC")
	database.InitDB(dsn)

	// 2. Setup Router
	r := gin.Default()
	api.RegisterGatewayRoutes(r)

	// 3. Start Server
	// Default to 8443, but plain HTTP for now as per MVP transition
	// Ideally this should use ListenAndServeTLS with mTLS config
	port := getEnvOrDefault("PORT", "8443")
	
	fmt.Printf("Agent Gateway listening on port %s\n", port)
	
	// TODO: Implement mTLS here
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to run HTTP server: %v", err)
	}
}
