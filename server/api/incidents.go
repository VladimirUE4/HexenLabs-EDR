package api

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hexenlabs/edr/server/database"
)

func GetIncidents(c *gin.Context) {
	var incidents []database.IncidentModel
	if err := database.DB.Order("created_at desc").Find(&incidents).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, incidents)
}

func CreateIncident(c *gin.Context) {
	var req struct {
		Title       string `json:"title" binding:"required"`
		Description string `json:"description" binding:"required"`
		Severity    string `json:"severity" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	incident := database.IncidentModel{
		ID:          fmt.Sprintf("inc-%d", time.Now().UnixNano()),
		Title:       req.Title,
		Description: req.Description,
		Severity:    req.Severity,
		Status:      "OPEN",
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}

	if err := database.DB.Create(&incident).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, incident)
}

func UpdateIncident(c *gin.Context) {
    id := c.Param("id")
    var req struct {
        Status     string `json:"status"`
        AssignedTo string `json:"assigned_to"`
    }

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    var incident database.IncidentModel
    if err := database.DB.First(&incident, "id = ?", id).Error; err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": "Incident not found"})
        return
    }

    if req.Status != "" {
        incident.Status = req.Status
    }
    // Allow empty string to unassign
    incident.AssignedTo = req.AssignedTo
    
    if req.AssignedTo != "" && incident.Status == "OPEN" {
        incident.Status = "ASSIGNED"
    }
    
    incident.UpdatedAt = time.Now()

    if err := database.DB.Save(&incident).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, incident)
}

// COMMENTS

func GetIncidentComments(c *gin.Context) {
    id := c.Param("id")
    var comments []database.IncidentCommentModel
    if err := database.DB.Where("incident_id = ?", id).Order("created_at asc").Find(&comments).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    c.JSON(http.StatusOK, comments)
}

func AddIncidentComment(c *gin.Context) {
    id := c.Param("id")
    var req struct {
        Author  string `json:"author" binding:"required"`
        Content string `json:"content" binding:"required"`
    }

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    comment := database.IncidentCommentModel{
        ID:         fmt.Sprintf("cmt-%d", time.Now().UnixNano()),
        IncidentID: id,
        Author:     req.Author,
        Content:    req.Content,
        CreatedAt:  time.Now(),
    }

    if err := database.DB.Create(&comment).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusCreated, comment)
}
