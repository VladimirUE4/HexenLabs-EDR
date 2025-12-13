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

func AgentHeartbeat(c *gin.Context) {
    var req struct {
        ID        string `json:"ID"`
        Hostname  string `json:"Hostname"`
        OsType    string `json:"OsType"`
        IpAddress string `json:"IpAddress"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    
    // Upsert Agent
    agent := database.AgentModel{
        ID:        req.ID,
        Hostname:  req.Hostname,
        OsType:    req.OsType,
        IpAddress: req.IpAddress,
        LastSeen:  time.Now(),
    }
    
    // Use Save (Upsert)
    if err := database.DB.Save(&agent).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    
    c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func GetNextTask(c *gin.Context) {
    agentID := c.Param("id")
    var cmd database.CommandModel
    
    // Find first PENDING command
    result := database.DB.Where("agent_id = ? AND status = ?", agentID, "PENDING").First(&cmd)
    if result.Error != nil {
        // No task
        c.Status(http.StatusNoContent)
        return
    }
    
    c.JSON(http.StatusOK, cmd)
}

func PostTaskResult(c *gin.Context) {
    // cmdID := c.Param("cmd_id")
    var req struct {
        OutputB64 string `json:"output_b64"`
        Error     string `json:"error"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    
    // Update Command
    cmdID := c.Param("cmd_id")
    
    updates := database.CommandModel{
        Status: "COMPLETED",
        Output: req.OutputB64, // We save B64 for now
    }
    if req.Error != "" {
        updates.Status = "FAILED"
        updates.Output = req.Error
    }
    
    database.DB.Model(&database.CommandModel{}).Where("id = ?", cmdID).Updates(updates)
    
    c.Status(http.StatusOK)
}
