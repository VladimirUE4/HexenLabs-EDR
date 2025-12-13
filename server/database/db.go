package database

import (
	"fmt"
	"log"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var DB *gorm.DB

type AgentModel struct {
	ID         string     `gorm:"primaryKey" json:"id"`
	Hostname   string     `json:"hostname"`
	OsType     string     `json:"os_type"`
	OsVersion  string     `json:"os_version"`
	IpAddress  string     `json:"ip_address"`
	AgentName  string     `json:"agent_name"`
	AgentGroup string     `json:"agent_group"`
	Status     string     `json:"status"`
	LastSeen   time.Time  `json:"last_seen"`
	CreatedAt  *time.Time `json:"created_at"`
}

type CommandModel struct {
	ID           string     `gorm:"primaryKey" json:"id"`
	AgentID      string     `json:"agent_id"`
	Type         string     `json:"type"`
	Payload      string     `json:"payload"`
	Status       string     `json:"status"`
	Output       string     `json:"output"`
	ResultOutput string     `json:"result_output"`
	ErrorMessage string     `json:"error_message"`
	CreatedAt    time.Time  `json:"created_at"`
	CompletedAt  *time.Time `json:"completed_at"`
}

func Connect() {
	dsn := "host=localhost user=postgres password=postgres dbname=hexen_edr port=5432 sslmode=disable"
	var err error
	DB, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Auto Migrate
	err = DB.AutoMigrate(&AgentModel{}, &CommandModel{})
	if err != nil {
		log.Printf("Failed to migrate database: %v", err)
	}
	
	fmt.Println("Database connected successfully.")
}

// Initialize DB on package load or explicitly? 
// For now, let's export Init/Connect and call it from main.
// Actually, to make handlers work immediately (since they use global DB), we need to ensure Connect is called.
