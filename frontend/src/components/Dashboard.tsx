import { Agent, getAgentId, getAgentHostname, getAgentOsType, getAgentStatus, getAgentLastSeen } from '../App'
import './Dashboard.css'

interface DashboardProps {
  agents: Agent[]
}

export default function Dashboard({ agents }: DashboardProps) {
  const onlineCount = agents.filter(a => getAgentStatus(a) === 'ONLINE').length
  const offlineCount = agents.length - onlineCount
  const osDistribution = agents.reduce((acc, agent) => {
    const os = getAgentOsType(agent)
    acc[os] = (acc[os] || 0) + 1
    return acc
  }, {} as Record<string, number>)

  return (
    <div className="dashboard">
      <div className="dashboard-header">
        <h2>Security Overview</h2>
        <span className="dashboard-subtitle">Real-time endpoint monitoring</span>
      </div>

      <div className="metrics-grid">
        <div className="metric-card">
          <div className="metric-icon blue">
            <i className="fas fa-server"></i>
          </div>
          <div className="metric-content">
            <span className="metric-label">Total Endpoints</span>
            <span className="metric-value">{agents.length}</span>
          </div>
        </div>

        <div className="metric-card">
          <div className="metric-icon green">
            <i className="fas fa-check-circle"></i>
          </div>
          <div className="metric-content">
            <span className="metric-label">Online</span>
            <span className="metric-value">{onlineCount}</span>
            <span className="metric-change positive">
              {agents.length > 0 ? Math.round((onlineCount / agents.length) * 100) : 0}%
            </span>
          </div>
        </div>

        <div className="metric-card">
          <div className="metric-icon red">
            <i className="fas fa-exclamation-circle"></i>
          </div>
          <div className="metric-content">
            <span className="metric-label">Offline</span>
            <span className="metric-value">{offlineCount}</span>
            <span className="metric-change negative">
              {agents.length > 0 ? Math.round((offlineCount / agents.length) * 100) : 0}%
            </span>
          </div>
        </div>

        <div className="metric-card">
          <div className="metric-icon purple">
            <i className="fas fa-shield-alt"></i>
          </div>
          <div className="metric-content">
            <span className="metric-label">Protection Status</span>
            <span className="metric-value">Active</span>
            <span className="metric-change positive">100% Coverage</span>
          </div>
        </div>
      </div>

      <div className="dashboard-grid">
        <div className="dashboard-card">
          <div className="card-header">
            <h3>OS Distribution</h3>
          </div>
          <div className="card-body">
            {Object.entries(osDistribution).map(([os, count]) => (
              <div key={os} className="distribution-item">
                <div className="distribution-label">
                  <i className={`fab fa-${os === 'linux' ? 'linux' : os === 'windows' ? 'windows' : 'apple'}`}></i>
                  <span>{os.charAt(0).toUpperCase() + os.slice(1)}</span>
                </div>
                <div className="distribution-bar">
                  <div
                    className="distribution-fill"
                    style={{
                      width: `${(count / agents.length) * 100}%`
                    }}
                  ></div>
                </div>
                <span className="distribution-value">{count}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="dashboard-card">
          <div className="card-header">
            <h3>Recent Activity</h3>
          </div>
          <div className="card-body">
            {agents.length === 0 ? (
              <div className="empty-activity">No activity to display</div>
            ) : (
              agents.slice(0, 5).map((agent) => {
                const status = getAgentStatus(agent)
                const isOnline = status === 'ONLINE'
                const hostname = getAgentHostname(agent)
                const lastSeen = getAgentLastSeen(agent)
                return (
                <div key={getAgentId(agent)} className="activity-item">
                  <div className="activity-icon">
                    <i className={`fas fa-${isOnline ? 'check-circle' : 'times-circle'}`}></i>
                  </div>
                  <div className="activity-content">
                    <span className="activity-text">
                      <strong>{hostname}</strong> is {status.toLowerCase()}
                    </span>
                    <span className="activity-time">
                      {lastSeen ? new Date(lastSeen).toLocaleString() : 'Never'}
                    </span>
                  </div>
                </div>
                )
              })
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

