package database

import (
	"fmt"
	"log"
	"os"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// AgentModel represents an enrolled agent
type AgentModel struct {
	ID           string    `gorm:"primaryKey"`
	Hostname     string
	OsType       string
	OsVersion    string
	IpAddress    string
	LastSeen     time.Time `gorm:"index"`
	Status       string    `gorm:"index"`
	AgentName    string    `gorm:"column:agent_name"`
	AgentGroup   string    `gorm:"column:agent_group;index"`
	CreatedAt    time.Time
}

// CommandModel represents a command to be executed or executed
type CommandModel struct {
	ID             string     `gorm:"primaryKey"`
	AgentID        string     `gorm:"index:idx_agent_status_created"`
	Type           string
	Payload        string     // JSON payload or raw string
	Status         string     `gorm:"index:idx_agent_status_created"` // PENDING, SENT, COMPLETED, ERROR
	ResultOutput   string
	ErrorMessage   string
	CreatedAt      time.Time  `gorm:"index:idx_agent_status_created"`
	CompletedAt    *time.Time
	DeletedAt      *time.Time `gorm:"index"` // Soft delete
}

// Global DB instance
var DB *gorm.DB

func InitDB(dsn string) {
	var err error
	// Use a secure logger configuration
	newLogger := logger.New(
		log.New(log.Writer(), "\r\n", log.LstdFlags), 
		logger.Config{
			SlowThreshold:             time.Second,
			LogLevel:                  logger.Warn,
			IgnoreRecordNotFoundError: true,
			Colorful:                  true,
		},
	)

	DB, err = gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: newLogger,
		PrepareStmt: true, // Cache statements for performance and security (prevents SQLi)
	})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// In production, use golang-migrate for versioned migrations
	// For dev, AutoMigrate is acceptable but not recommended for prod
	// Check if we're in dev mode (you can set MIGRATE_MODE=auto env var)
	migrateMode := os.Getenv("MIGRATE_MODE")
	if migrateMode == "auto" || migrateMode == "" {
		err = DB.AutoMigrate(&AgentModel{}, &CommandModel{})
		if err != nil {
			log.Fatalf("Failed to migrate database: %v", err)
		}
		fmt.Println("Database connection established and schema migrated (AutoMigrate).")
	} else {
		fmt.Println("Database connection established. Run migrations manually with: migrate -path migrations -database \"DSN\" up")
	}
}


