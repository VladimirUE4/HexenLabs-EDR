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
	fmt.Println("HexenLabs EDR Backend API Starting...")

	// 1. Init Database
	dsn := getEnvOrDefault("DATABASE_DSN", "host=localhost user=postgres password=postgres dbname=hexen_edr port=5432 sslmode=disable TimeZone=UTC")
	database.InitDB(dsn)

	// 2. Setup Router
	r := gin.Default()
	api.RegisterBackendRoutes(r)

	// 3. Start Server
	port := getEnvOrDefault("PORT", "8080")
	fmt.Printf("Backend API listening on port %s\n", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to run HTTP server: %v", err)
	}
}

