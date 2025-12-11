package api

import (
	"encoding/base64"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hexenlabs/edr/server/database"
)


func AgentHeartbeat(c *gin.Context) {
	var req struct {
		ID         string `json:"ID" binding:"required"`
		Hostname   string `json:"Hostname" binding:"required"`
		OsType     string `json:"OsType" binding:"required"`
		IpAddress  string `json:"IpAddress"`
		OsVersion  string `json:"OsVersion"`
		Name       string `json:"Name"`
		Group      string `json:"Group"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Update or Create
	var agent database.AgentModel
	if err := database.DB.First(&agent, "id = ?", req.ID).Error; err != nil {
		// Create new agent
		newAgent := database.AgentModel{
			ID:         req.ID,
			Hostname:   req.Hostname,
			OsType:     req.OsType,
			OsVersion:  req.OsVersion,
			IpAddress:  req.IpAddress,
			AgentName:  req.Name,
			AgentGroup: req.Group,
			LastSeen:   time.Now(),
			Status:     "ONLINE",
			CreatedAt:  time.Now(),
		}
		database.DB.Create(&newAgent)
	} else {
		// Update existing
		agent.LastSeen = time.Now()
		agent.Status = "ONLINE"
		agent.IpAddress = req.IpAddress
		if req.Name != "" {
			agent.AgentName = req.Name
		}
		if req.Group != "" {
			agent.AgentGroup = req.Group
		}
		database.DB.Save(&agent)
	}
	c.Status(http.StatusOK)
}

func GetNextTask(c *gin.Context) {
	agentID := c.Param("id")
	var cmd database.CommandModel
	
	// Find oldest PENDING command
	if err := database.DB.Where("agent_id = ? AND status = ?", agentID, "PENDING").Order("created_at asc").First(&cmd).Error; err != nil {
		c.Status(http.StatusNoContent) // No work
		return
	}

	// Mark as SENT
	cmd.Status = "SENT"
	database.DB.Save(&cmd)

	c.JSON(http.StatusOK, cmd)
}

func PostTaskResult(c *gin.Context) {
	cmdID := c.Param("cmd_id")
	var req struct {
		Output    string `json:"output"`
		OutputB64 string `json:"output_b64"`
		Error     string `json:"error"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var cmd database.CommandModel
	if err := database.DB.First(&cmd, "id = ?", cmdID).Error; err != nil {
		c.Status(http.StatusNotFound)
		return
	}

	// Handle B64 decoding if present
	if req.OutputB64 != "" {
		decoded, err := base64.StdEncoding.DecodeString(req.OutputB64)
		if err == nil {
			cmd.ResultOutput = string(decoded)
		} else {
			cmd.ResultOutput = "Error decoding base64 output"
		}
	} else {
		cmd.ResultOutput = req.Output
	}

	cmd.ErrorMessage = req.Error
	if req.Error != "" {
		cmd.Status = "ERROR"
	} else {
		cmd.Status = "COMPLETED"
	}
	now := time.Now()
	cmd.CompletedAt = &now
	database.DB.Save(&cmd)
	
	c.Status(http.StatusOK)
}

