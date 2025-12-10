package database

import (
	"fmt"
	"log"
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
	Status       string
	CreatedAt    time.Time
}

// CommandModel represents a command to be executed or executed
type CommandModel struct {
	ID             string    `gorm:"primaryKey"`
	AgentID        string    `gorm:"index"`
	Type           string
	Payload        string    // JSON payload or raw string
	Status         string    // PENDING, SENT, COMPLETED, ERROR
	ResultOutput   string
	ErrorMessage   string
	CreatedAt      time.Time
	CompletedAt    *time.Time
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

	// AutoMigrate is convenient for dev, but in prod use migration files (e.g. golang-migrate)
	// We use it here to set up the schema quickly.
	err = DB.AutoMigrate(&AgentModel{}, &CommandModel{})
	if err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}
	
	fmt.Println("Database connection established and schema migrated.")
}

