import type { Agent } from '../App';
import { getAgentId, getAgentHostname, getAgentOsType, getAgentOsVersion, getAgentIpAddress, getAgentStatus, getAgentLastSeen } from '../App';
import './AgentList.css';

interface AgentListProps {
  agents: Agent[];
  onSelectAgent: (agent: Agent) => void
}

export default function AgentList({ agents, onSelectAgent }: AgentListProps) {
  if (agents.length === 0) {
    return (
      <div className="empty-state">
        <i className="fas fa-server"></i>
        <p>No agents enrolled yet</p>
        <span className="empty-subtitle">Start the agent executable to begin monitoring</span>
      </div>
    )
  }

  return (
    <div className="agents-grid">
      {agents.map((agent) => {
        const lastSeenStr = getAgentLastSeen(agent)
        const lastSeen = lastSeenStr ? new Date(lastSeenStr) : new Date(0)
        const status = getAgentStatus(agent)
        const isOnline = status === 'ONLINE'
        const timeSince = Math.floor((Date.now() - lastSeen.getTime()) / 1000)
        const timeAgo = timeSince < 60 ? `${timeSince}s ago` : 
                       timeSince < 3600 ? `${Math.floor(timeSince / 60)}m ago` :
                       `${Math.floor(timeSince / 3600)}h ago`

        const agentId = getAgentId(agent)
        const hostname = getAgentHostname(agent)
        const osType = getAgentOsType(agent)
        const osVersion = getAgentOsVersion(agent)
        const ipAddress = getAgentIpAddress(agent)

        return (
          <div
            key={agentId}
            className={`agent-card-xdr ${isOnline ? 'online' : 'offline'}`}
            onClick={() => onSelectAgent(agent)}
          >
            <div className="agent-card-header">
              <div className="agent-status-indicator">
                <div className={`status-pulse ${isOnline ? 'active' : ''}`}></div>
                <div className={`status-dot-xdr ${isOnline ? 'online' : 'offline'}`}></div>
              </div>
              <div className="agent-info-main">
                <h3 className="agent-hostname">
                  <i className={`fab fa-${osType === 'linux' ? 'linux' : osType === 'windows' ? 'windows' : 'apple'}`}></i>
                  {hostname}
                </h3>
                <span className="agent-id">{agentId.substring(0, 8)}...</span>
              </div>
            </div>

            <div className="agent-card-body">
              <div className="agent-metric">
                <span className="metric-label">OS</span>
                <span className="metric-value">{osType} {osVersion}</span>
              </div>
              <div className="agent-metric">
                <span className="metric-label">IP Address</span>
                <span className="metric-value">{ipAddress}</span>
              </div>
              <div className="agent-metric">
                <span className="metric-label">Last Seen</span>
                <span className="metric-value">{timeAgo}</span>
              </div>
            </div>

            <div className="agent-card-footer">
              <span className={`status-badge ${isOnline ? 'online' : 'offline'}`}>
                {status}
              </span>
            </div>
          </div>
        )
      })}
    </div>
  )
}
