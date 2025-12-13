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
	Signature    string     `json:"signature"` // Ed25519 Signature
	Status       string     `json:"status"`
	Output       string     `json:"output"`
	ResultOutput string     `json:"result_output"`
	ErrorMessage string     `json:"error_message"`
	CreatedAt    time.Time  `json:"created_at"`
	CompletedAt  *time.Time `json:"completed_at"`
}

type IncidentModel struct {
    ID          string     `gorm:"primaryKey" json:"id"`
    Title       string     `json:"title"`
    Description string     `json:"description"`
    Severity    string     `json:"severity"` // LOW, MEDIUM, HIGH, CRITICAL
    Status      string     `json:"status"`   // OPEN, ASSIGNED, RESOLVED, CLOSED
    AssignedTo  string     `json:"assigned_to"` // User name or ID
    CreatedAt   time.Time  `json:"created_at"`
    UpdatedAt   time.Time  `json:"updated_at"`
}

type IncidentCommentModel struct {
    ID         string    `gorm:"primaryKey" json:"id"`
    IncidentID string    `gorm:"index" json:"incident_id"`
    Author     string    `json:"author"`
    Content    string    `json:"content"`
    CreatedAt  time.Time `json:"created_at"`
}



func Connect() {
	dsn := "host=localhost user=postgres password=postgres dbname=hexen_edr port=5432 sslmode=disable"
	var err error
	DB, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Auto Migrate
	err = DB.AutoMigrate(&AgentModel{}, &CommandModel{}, &IncidentModel{}, &IncidentCommentModel{})
	if err != nil {
		log.Printf("Failed to migrate database: %v", err)
	}
	
	fmt.Println("Database connected successfully.")
}

// Initialize DB on package load or explicitly? 
// For now, let's export Init/Connect and call it from main.
// Actually, to make handlers work immediately (since they use global DB), we need to ensure Connect is called.

