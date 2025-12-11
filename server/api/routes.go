package api

import (
	"github.com/gin-gonic/gin"
	"github.com/hexenlabs/edr/server/auth"
)

// RegisterBackendRoutes registers routes for the Frontend/Dashboard
func RegisterBackendRoutes(r *gin.Engine) {
	// CORS middleware for React frontend
	r.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "http://localhost:3000")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	})

	// Public Auth Routes
	r.POST("/api/auth/login", auth.Login)
	r.POST("/api/auth/refresh", auth.Refresh)

	// Protected Routes (JWT Required)
	protected := r.Group("/api")
	protected.Use(auth.AuthMiddleware())
	{
		protected.GET("/auth/me", auth.Me)
		protected.GET("/agents", GetAgents)
		protected.POST("/agents/:id/osquery", QueueOsqueryCommand)
		protected.GET("/agents/:id/commands", GetAgentCommands)
	}
}

// RegisterGatewayRoutes registers routes for Agents
func RegisterGatewayRoutes(r *gin.Engine) {
	// No CORS needed for agents usually, or restricted
	// No JWT Auth for now (mTLS will be handled at listener level or via middleware later)
	
	api := r.Group("/api")
	{
		api.POST("/heartbeat", AgentHeartbeat)
		api.GET("/agents/:id/tasks/next", GetNextTask)
		api.POST("/agents/:id/tasks/:cmd_id/result", PostTaskResult)
	}
}

