package api

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hexenlabs/edr/server/database"
)

func RegisterRoutes(r *gin.Engine) {
	api := r.Group("/api")
	{
		api.GET("/agents", GetAgents)
		api.POST("/heartbeat", AgentHeartbeat) // NEW
		api.POST("/agents/:id/osquery", QueueOsqueryCommand)
		api.GET("/agents/:id/commands", GetAgentCommands)
		api.GET("/agents/:id/tasks/next", GetNextTask) // NEW
        api.POST("/agents/:id/tasks/:cmd_id/result", PostTaskResult) // NEW
	}
	// Serve frontend
	r.Static("/static", "./web/static")
	r.StaticFile("/", "./web/index.html")
}

func GetAgents(c *gin.Context) {
	var agents []database.AgentModel
	result := database.DB.Find(&agents)
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": result.Error.Error()})
		return
	}
	c.JSON(http.StatusOK, agents)
}

func QueueOsqueryCommand(c *gin.Context) {
	agentID := c.Param("id")
	var req struct {
		Query string `json:"query" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
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
