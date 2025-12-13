import { useState, useEffect } from 'react'
import axios from 'axios'
import DOMPurify from 'dompurify'
import { Agent, getAgentId, getAgentHostname, getAgentOsType } from '../App'
import './AgentModal.css'

interface AgentModalProps {
  agent: Agent
  onClose: () => void
}

interface Command {
  ID: string
  Payload: string
  Status: string
  ResultOutput: string
  ErrorMessage: string
  CreatedAt: string
}

export default function AgentModal({ agent, onClose }: AgentModalProps) {
  const [commands, setCommands] = useState<Command[]>([])
  const [query, setQuery] = useState('SELECT pid, name, path FROM processes LIMIT 5;')
  const [loading, setLoading] = useState(false)

  const agentId = getAgentId(agent)
  
  const fetchCommands = async () => {
    try {
      const res = await axios.get<Command[]>(`/api/agents/${agentId}/commands`)
      setCommands(res.data)
    } catch (err) {
      console.error('Failed to fetch commands:', err)
    }
  }

  useEffect(() => {
    fetchCommands()
    const interval = setInterval(fetchCommands, 2000)
    return () => clearInterval(interval)
  }, [agentId])

  const executeQuery = async () => {
    if (!query.trim()) return

    setLoading(true)
    try {
      await axios.post(`/api/agents/${agentId}/osquery`, { query })
      await fetchCommands()
    } catch (err) {
      console.error('Failed to execute query:', err)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="modal-overlay-xdr" onClick={onClose}>
      <div className="modal-content-xdr" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header-xdr">
          <div className="modal-header-left">
            <div className="modal-agent-icon">
              <i className={`fab fa-${getAgentOsType(agent) === 'linux' ? 'linux' : getAgentOsType(agent) === 'windows' ? 'windows' : 'apple'}`}></i>
            </div>
            <div>
              <h3>{getAgentHostname(agent)}</h3>
              <span className="modal-agent-id">{agentId}</span>
            </div>
          </div>
          <button className="close-btn-xdr" onClick={onClose}>
            <i className="fas fa-times"></i>
          </button>
        </div>

        <div className="modal-body-xdr">
          <div className="modal-left-xdr">
            <div className="section-header">
              <i className="fas fa-terminal"></i>
              <h4>Live Query (Osquery)</h4>
            </div>
            <textarea
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="query-input-xdr"
              rows={6}
              placeholder="SELECT * FROM processes..."
            />
            <button
              onClick={executeQuery}
              disabled={loading}
              className="btn-execute-xdr"
            >
              {loading ? (
                <>
                  <i className="fas fa-spinner fa-spin"></i> Executing...
                </>
              ) : (
                <>
                  <i className="fas fa-play"></i> Execute Query
                </>
              )}
            </button>

            <div className="presets-section">
              <div className="section-header">
                <i className="fas fa-bookmark"></i>
                <h4>Presets</h4>
              </div>
              <div className="presets-grid">
                <button onClick={() => setQuery('SELECT * FROM users;')} className="preset-btn">
                  <i className="fas fa-users"></i>
                  <span>List Users</span>
                </button>
                <button onClick={() => setQuery('SELECT * FROM listening_ports;')} className="preset-btn">
                  <i className="fas fa-network-wired"></i>
                  <span>Open Ports</span>
                </button>
                <button onClick={() => setQuery('SELECT * FROM startup_items;')} className="preset-btn">
                  <i className="fas fa-rocket"></i>
                  <span>Startup Items</span>
                </button>
                <button onClick={() => setQuery('SELECT * FROM processes;')} className="preset-btn">
                  <i className="fas fa-tasks"></i>
                  <span>All Processes</span>
                </button>
              </div>
            </div>
          </div>

          <div className="modal-right-xdr">
            <div className="section-header">
              <i className="fas fa-history"></i>
              <h4>Execution History</h4>
              {commands.some(c => c.Status === 'PENDING' || c.Status === 'SENT') && (
                <span className="live-indicator">
                  <i className="fas fa-circle"></i> Live
                </span>
              )}
            </div>
            <div className="command-history-xdr">
              {commands.length === 0 ? (
                <div className="empty-commands">No commands executed yet</div>
              ) : (
                commands.map((cmd) => {
                  let statusClass = 'status-pending'
                  let statusIcon = 'fa-clock'
                  if (cmd.Status === 'COMPLETED') {
                    statusClass = 'status-completed'
                    statusIcon = 'fa-check-circle'
                  } else if (cmd.Status === 'ERROR') {
                    statusClass = 'status-error'
                    statusIcon = 'fa-times-circle'
                  } else if (cmd.Status === 'SENT') {
                    statusClass = 'status-sent'
                    statusIcon = 'fa-paper-plane'
                  }

                  let resultHtml = ''
                  if (cmd.ResultOutput) {
                    try {
                      const json = JSON.parse(cmd.ResultOutput)
                      resultHtml = JSON.stringify(json, null, 2)
                    } catch (e) {
                      resultHtml = cmd.ResultOutput
                    }
                    // Sanitize HTML to prevent XSS
                    resultHtml = DOMPurify.sanitize(resultHtml, { ALLOWED_TAGS: [] })
                  }

                  return (
                    <div key={cmd.ID} className="command-card-xdr">
                      <div className="command-header-xdr">
                        <div className="command-status">
                          <span className={`status-badge-xdr ${statusClass}`}>
                            <i className={`fas ${statusIcon}`}></i>
                            {cmd.Status}
                          </span>
                          <span className="command-id">{cmd.ID.substring(0, 12)}...</span>
                        </div>
                        <span className="command-time">
                          {new Date(cmd.CreatedAt).toLocaleTimeString()}
                        </span>
                      </div>
                      <div className="command-payload-xdr">
                        <code>{cmd.Payload}</code>
                      </div>
                      {cmd.ResultOutput && (
                        <pre className="command-output-xdr" dangerouslySetInnerHTML={{ __html: resultHtml }}></pre>
                      )}
                      {cmd.ErrorMessage && (
                        <div className="command-error-xdr">
                          <i className="fas fa-exclamation-triangle"></i>
                          {DOMPurify.sanitize(cmd.ErrorMessage, { ALLOWED_TAGS: [] })}
                        </div>
                      )}
                    </div>
                  )
                })
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
