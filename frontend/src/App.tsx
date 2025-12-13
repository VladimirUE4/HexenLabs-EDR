import { useState, useEffect, useCallback } from 'react'
import axios from 'axios'
import AgentList from './components/AgentList'
import AgentModal from './components/AgentModal'
import Dashboard from './components/Dashboard'
import Login from './auth/Login'
import { useAuth } from './auth/AuthContext'
import './App.css'

const API_BASE = '/api'

export interface Agent {
  id?: string
  ID?: string
  hostname?: string
  Hostname?: string
  os_type?: string
  OsType?: string
  os_version?: string
  OsVersion?: string
  ip_address?: string
  IpAddress?: string
  status?: string
  Status?: string
  last_seen?: string
  LastSeen?: string
}

// Helper functions to access agent properties (handles both snake_case and PascalCase)
export const getAgentId = (agent: Agent) => agent.ID || agent.id || ''
export const getAgentHostname = (agent: Agent) => agent.Hostname || agent.hostname || 'Unknown'
export const getAgentOsType = (agent: Agent) => agent.OsType || agent.os_type || 'unknown'
export const getAgentOsVersion = (agent: Agent) => agent.OsVersion || agent.os_version || ''
export const getAgentIpAddress = (agent: Agent) => agent.IpAddress || agent.ip_address || ''
export const getAgentStatus = (agent: Agent) => agent.Status || agent.status || 'OFFLINE'
export const getAgentLastSeen = (agent: Agent) => agent.LastSeen || agent.last_seen || ''

function App() {
  const { isAuthenticated, loading: authLoading, logout } = useAuth()
  const [agents, setAgents] = useState<Agent[]>([])
  const [selectedAgent, setSelectedAgent] = useState<Agent | null>(null)
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState<'dashboard' | 'agents'>('dashboard')
  const [sidebarOpen, setSidebarOpen] = useState(false)

  const fetchAgents = useCallback(async () => {
    try {
      const res = await axios.get<Agent[]>(`${API_BASE}/agents`)
      setAgents(res.data)
    } catch (err) {
      console.error('Failed to fetch agents:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (isAuthenticated && !authLoading) {
      fetchAgents()
      const interval = setInterval(fetchAgents, 5000)
      return () => clearInterval(interval)
    }
  }, [isAuthenticated, authLoading, fetchAgents])

  if (authLoading) {
    return (
      <div className="loading-container">
        <div className="spinner"></div>
        <p>Loading...</p>
      </div>
    )
  }

  if (!isAuthenticated) {
    return <Login />
  }

  const onlineCount = agents.filter(a => getAgentStatus(a) === 'ONLINE').length
  const offlineCount = agents.length - onlineCount

  return (
    <div className="app-xdr">
      <nav className="navbar-xdr">
        <div className="nav-container">
          <div className="nav-left">
            <button 
              className="hamburger-btn"
              onClick={() => setSidebarOpen(!sidebarOpen)}
              aria-label="Toggle menu"
            >
              <i className="fas fa-bars"></i>
            </button>
            <div className="nav-brand">
              <div className="brand-icon">
                <svg width="40" height="40" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path fillRule="evenodd" clipRule="evenodd" d="M1 7L4.80061 1.43926C5.56059 0.527292 6.68638 0 7.8735 0H8V4L12 5L15 10L14.1875 11.2188C13.4456 12.3316 12.1967 13 10.8593 13H9L7 16H5L1 7ZM10 9C10.5523 9 11 8.55229 11 8C11 7.44772 10.5523 7 10 7C9.44771 7 9 7.44772 9 8C9 8.55229 9.44771 9 10 9Z" fill="currentColor"/>
                  <path d="M10 0.465878V2.43845L12 2.93845V0H11.8735C11.2125 0 10.5704 0.163501 10 0.465878Z" fill="currentColor"/>
                </svg>
              </div>
              <div>
                <h1 className="brand-title">HexenLabs</h1>
                <span className="brand-subtitle">Extended Detection & Response</span>
              </div>
            </div>
          </div>
          <div className="nav-stats">
            <div className="stat-item">
              <span className="stat-value">{agents.length}</span>
              <span className="stat-label">Total Agents</span>
            </div>
            <div className="stat-item online">
              <span className="stat-value">{onlineCount}</span>
              <span className="stat-label">Online</span>
            </div>
            <div className="stat-item offline">
              <span className="stat-value">{offlineCount}</span>
              <span className="stat-label">Offline</span>
            </div>
            <button onClick={logout} className="logout-btn">
              <i className="fas fa-sign-out-alt"></i> Logout
            </button>
          </div>
        </div>
      </nav>

      <div className="main-container">
        {sidebarOpen && (
          <div className="sidebar-overlay" onClick={() => setSidebarOpen(false)}></div>
        )}
        <div className={`sidebar ${sidebarOpen ? 'open' : ''}`}>
          <div className="sidebar-menu">
            <button
              className={`menu-item ${activeTab === 'dashboard' ? 'active' : ''}`}
              onClick={() => {
                setActiveTab('dashboard')
                setSidebarOpen(false)
              }}
            >
              <i className="fas fa-chart-line"></i>
              <span>Dashboard</span>
            </button>
            <button
              className={`menu-item ${activeTab === 'agents' ? 'active' : ''}`}
              onClick={() => {
                setActiveTab('agents')
                setSidebarOpen(false)
              }}
            >
              <i className="fas fa-server"></i>
              <span>Endpoints</span>
            </button>
          </div>
        </div>

        <div className="content-area">
          {activeTab === 'dashboard' ? (
            <Dashboard agents={agents} />
          ) : (
            <>
              <div className="page-header">
                <h2>Endpoints</h2>
                <button onClick={fetchAgents} className="btn-refresh">
                  <i className="fas fa-sync-alt"></i> Refresh
                </button>
              </div>

              {loading ? (
                <div className="loading-container">
                  <div className="spinner"></div>
                  <p>Loading agents...</p>
                </div>
              ) : (
                <AgentList
                  agents={agents}
                  onSelectAgent={(agent) => setSelectedAgent(agent)}
                />
              )}

              {selectedAgent && (
                <AgentModal
                  agent={selectedAgent}
                  onClose={() => setSelectedAgent(null)}
                />
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

export default App
