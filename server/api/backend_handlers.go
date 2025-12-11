package api

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hexenlabs/edr/server/database"
)

func GetAgents(c *gin.Context) {
	var agents []database.AgentModel
	result := database.DB.Find(&agents)
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": result.Error.Error()})
		return
	}

	// Update status based on LastSeen (30 second timeout)
	now := time.Now()
	for i := range agents {
		timeSinceLastSeen := now.Sub(agents[i].LastSeen)
		if timeSinceLastSeen > 30*time.Second {
			agents[i].Status = "OFFLINE"
			// Update in DB
			database.DB.Model(&agents[i]).Update("status", "OFFLINE")
		} else {
			agents[i].Status = "ONLINE"
		}
	}

	c.JSON(http.StatusOK, agents)
}

func QueueOsqueryCommand(c *gin.Context) {
	agentID := c.Param("id")
	var req struct {
		Query string `json:"query" binding:"required,min=1,max=10000"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Basic validation: must start with SELECT
	queryUpper := strings.ToUpper(strings.TrimSpace(req.Query))
	if !strings.HasPrefix(queryUpper, "SELECT") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only SELECT queries are allowed"})
		return
	}

	// Check for dangerous keywords
	dangerous := []string{"INSERT", "UPDATE", "DELETE", "DROP", "CREATE", "ALTER", "EXEC", "EXECUTE", "TRUNCATE"}
	for _, keyword := range dangerous {
		if strings.Contains(queryUpper, keyword) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Dangerous keyword detected: " + keyword})
			return
		}
	}

	// Create Command in DB
	cmd := database.CommandModel{
		ID:        fmt.Sprintf("cmd-%d", time.Now().UnixNano()),
		AgentID:   agentID,
		Type:      "OSQUERY",
		Payload:   req.Query,
		Status:    "PENDING", // Agent will pick this up
		CreatedAt: time.Now(),
	}

	if err := database.DB.Create(&cmd).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, cmd)
}

func GetAgentCommands(c *gin.Context) {
	agentID := c.Param("id")
	var commands []database.CommandModel
	// Limit to last 50 for performance
	if err := database.DB.Where("agent_id = ?", agentID).Order("created_at desc").Limit(50).Find(&commands).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, commands)
}

