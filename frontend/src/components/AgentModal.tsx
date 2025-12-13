import { useState, useEffect, useRef } from 'react'
import axios from 'axios'
import DOMPurify from 'dompurify'
import { Agent, getAgentId, getAgentHostname, getAgentOsType } from '../App'
import { Terminal, Package, Activity, Clock, Play, Command as CommandIcon, Trash2 } from 'lucide-react'
import nacl from 'tweetnacl'
import { decode as decodeHex, encode as encodeHex } from 'tweetnacl-util'
import './AgentModal.css'

interface AgentModalProps {
  agent: Agent
  onClose: () => void
}

interface Command {
  id?: string
  ID?: string
  payload?: string
  Payload?: string
  status?: string
  Status?: string
  result_output?: string
  ResultOutput?: string
  error_message?: string
  ErrorMessage?: string
  created_at?: string
  CreatedAt?: string
  type?: string
  Type?: string
}

// ADMIN PRIVATE KEY (For Demo Only - In prod this stays in YubiKey/Secure Storage)
// Corresponds to Public Key: fe3012be0c173015cc27f25c8c52b7a62da031600bde3b062439bd25fb6df497
const ADMIN_PRIV_KEY_HEX = "2f7d04aff1982f68b8f8643f55c61ae94722cb49899d20a4d50f4787dd80d938fe3012be0c173015cc27f25c8c52b7a62da031600bde3b062439bd25fb6df497";

// Helper functions
const getCommandId = (cmd: Command) => cmd.ID || cmd.id || ''
const getCommandPayload = (cmd: Command) => cmd.Payload || cmd.payload || ''
const getCommandStatus = (cmd: Command) => cmd.Status || cmd.status || 'UNKNOWN'
const getCommandResultOutput = (cmd: Command) => cmd.ResultOutput || cmd.result_output || ''
const getCommandErrorMessage = (cmd: Command) => cmd.ErrorMessage || cmd.error_message || ''
const getCommandCreatedAt = (cmd: Command) => cmd.CreatedAt || cmd.created_at || ''
const getCommandType = (cmd: Command) => cmd.Type || cmd.type || 'OSQUERY'

// Convert Hex string to Uint8Array
const hexToBytes = (hex: string): Uint8Array => {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
    }
    return bytes;
}

// Convert Uint8Array to Hex string
const bytesToHex = (bytes: Uint8Array): string => {
    return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
}

const signPayload = (payload: string): string => {
    const privKey = hexToBytes(ADMIN_PRIV_KEY_HEX);
    const msgBytes = new TextEncoder().encode(payload);
    // Sign the message (Ed25519)
    // nacl.sign.detached returns the signature only
    const signature = nacl.sign.detached(msgBytes, privKey);
    return bytesToHex(signature);
}

export default function AgentModal({ agent, onClose }: AgentModalProps) {
  const [activeTab, setActiveTab] = useState<'osquery' | 'terminal' | 'software'>('osquery')
  const [commands, setCommands] = useState<Command[]>([])
  const [query, setQuery] = useState('SELECT pid, name, path FROM processes LIMIT 10;')
  const [shellCmd, setShellCmd] = useState('')
  const [loading, setLoading] = useState(false)
  const [softwareLoading, setSoftwareLoading] = useState(false)
  const [clearedAt, setClearedAt] = useState<number>(0)
  
  // Terminal emulation state
  const terminalEndRef = useRef<HTMLDivElement>(null)

  const agentId = getAgentId(agent)
  
  const fetchCommands = async () => {
    try {
      const res = await axios.get<Command[]>(`/api/agents/${agentId}/commands`)
      // Sort by date desc
      const sorted = res.data.sort((a, b) => {
          const dateA = new Date(getCommandCreatedAt(a)).getTime()
          const dateB = new Date(getCommandCreatedAt(b)).getTime()
          return dateB - dateA
      })
      setCommands(sorted)
    } catch (err) {
      console.error('Failed to fetch commands:', err)
    }
  }
  
  // Filter commands based on clearedAt timestamp
  const visibleCommands = commands.filter(cmd => {
      const cmdTime = new Date(getCommandCreatedAt(cmd)).getTime()
      return cmdTime > clearedAt
  })

  useEffect(() => {
    fetchCommands()
    const interval = setInterval(fetchCommands, 2000)
    return () => clearInterval(interval)
  }, [agentId])

  // Scroll to bottom of terminal when new commands arrive (if tab is terminal)
  useEffect(() => {
      if (activeTab === 'terminal') {
          terminalEndRef.current?.scrollIntoView({ behavior: "smooth" })
      }
  }, [visibleCommands, activeTab])

  const executeTask = async (payload: string, type: 'OSQUERY' | 'SHELL') => {
    if (!payload.trim()) return

    setLoading(true)
    try {
        // SIGN THE PAYLOAD
        const signature = signPayload(payload);
        
        await axios.post(`/api/agents/${agentId}/osquery`, { 
            query: payload, 
            type: type,
            signature: signature 
        })
        await fetchCommands()
        if (type === 'SHELL') setShellCmd('')
    } catch (err) {
      console.error('Failed to execute task:', err)
    } finally {
      setLoading(false)
    }
  }

  const fetchSoftware = async () => {
      setSoftwareLoading(true)
      const osType = getAgentOsType(agent)
      let query = ""
      // Broad query to cover most Linux distros
      if (osType === 'linux') {
          query = "SELECT name, version, source FROM deb_packages UNION SELECT name, version, source FROM rpm_packages UNION SELECT name, version, 'pacman' as source FROM pacman_packages;"
      } else if (osType === 'windows') {
          query = "SELECT name, version, source FROM programs;" 
      } else {
          // macOS
          query = "SELECT name, version, source FROM apps;"
      }
      
      try {
          const signature = signPayload(query);
          await axios.post(`/api/agents/${agentId}/osquery`, { 
              query: query, 
              type: 'OSQUERY',
              signature: signature 
          })
          alert("Software scan started. Results will appear in Execution History shortly.")
      } catch(e) {
          console.error(e)
      } finally {
          setSoftwareLoading(false)
      }
  }

  const clearTerminal = () => {
      setClearedAt(Date.now())
      // alert("Terminal cleared"); // No need for alert, UI updates instantly
  }

  const handleShellKeyDown = (e: React.KeyboardEvent) => {
      if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault()
          executeTask(shellCmd, 'SHELL')
      }
  }

  return (
    <div className="modal-overlay-xdr" onClick={onClose}>
      <div className="modal-content-xdr" onClick={(e) => e.stopPropagation()}>
        
        {/* Header */}
        <div className="modal-header-xdr">
          <div className="modal-header-left">
            <div className="modal-agent-icon">
              <i className={`fab fa-${getAgentOsType(agent) === 'linux' ? 'linux' : getAgentOsType(agent) === 'windows' ? 'windows' : 'apple'}`}></i>
            </div>
            <div>
              <h3>{getAgentHostname(agent)}</h3>
              <span className="modal-agent-id">{agentId}</span>
              <span className="security-badge"><i className="fas fa-lock"></i> Ed25519 Secured</span>
            </div>
          </div>
          <button className="close-btn-xdr" onClick={onClose}>×</button>
        </div>

        {/* Tabs */}
        <div className="modal-tabs">
            <button className={`tab-btn ${activeTab === 'osquery' ? 'active' : ''}`} onClick={() => setActiveTab('osquery')}>
                <Activity size={18} /> Osquery
            </button>
            <button className={`tab-btn ${activeTab === 'terminal' ? 'active' : ''}`} onClick={() => setActiveTab('terminal')}>
                <Terminal size={18} /> Terminal
            </button>
            <button className={`tab-btn ${activeTab === 'software' ? 'active' : ''}`} onClick={() => setActiveTab('software')}>
                <Package size={18} /> Software
            </button>
        </div>

        <div className="modal-body-xdr">
          
          {/* LEFT PANEL */}
          <div className="modal-left-xdr">
            
            {activeTab === 'osquery' && (
                <div className="tab-content fade-in">
                    <div className="section-header">
                        <Activity size={18} />
                        <h4>Live Query Builder</h4>
                    </div>
                    
                    <div className="query-editor">
                        <textarea
                            value={query}
                            onChange={(e) => setQuery(e.target.value)}
                            className="query-input-xdr"
                            rows={5}
                            spellCheck={false}
                        />
                        <button
                            onClick={() => executeTask(query, 'OSQUERY')}
                            disabled={loading}
                            className="btn-execute-xdr"
                        >
                            {loading ? <i className="fas fa-spinner fa-spin"></i> : <Play size={16} />} Run Query
                        </button>
                    </div>

                    <div className="presets-section">
                        <h4><CommandIcon size={16}/> Quick Presets</h4>
                        <div className="presets-grid">
                            <button onClick={() => setQuery('SELECT * FROM users;')} className="preset-btn">Users</button>
                            <button onClick={() => setQuery('SELECT * FROM processes LIMIT 20;')} className="preset-btn">Processes</button>
                            <button onClick={() => setQuery('SELECT * FROM listening_ports;')} className="preset-btn">Open Ports</button>
                            <button onClick={() => setQuery('SELECT * FROM logged_in_users;')} className="preset-btn">Logged In</button>
                            <button onClick={() => setQuery('SELECT * FROM usb_devices;')} className="preset-btn">USB Devices</button>
                            <button onClick={() => setQuery('SELECT * FROM startup_items;')} className="preset-btn">Startup</button>
                        </div>
                    </div>
                </div>
            )}

            {activeTab === 'terminal' && (
                <div className="tab-content fade-in terminal-mode">
                    <div className="terminal-header-actions">
                        <button className="btn-clear-term" onClick={clearTerminal}>
                            <Trash2 size={14} /> Clear Session
                        </button>
                    </div>
                    <div className="terminal-display">
                        {visibleCommands.filter(c => getCommandType(c) === 'SHELL').slice().reverse().map(cmd => (
                            <div key={getCommandId(cmd)} className="terminal-entry">
                                <div className="term-cmd">
                                    <span className="prompt">agent&gt;</span> {getCommandPayload(cmd)}
                                </div>
                                {getCommandResultOutput(cmd) && (
                                    <pre className="term-output">{getCommandResultOutput(cmd)}</pre>
                                )}
                                {getCommandErrorMessage(cmd) && (
                                    <div className="term-error">{getCommandErrorMessage(cmd)}</div>
                                )}
                                {getCommandStatus(cmd) === 'PENDING' && <div className="term-loading">...</div>}
                            </div>
                        ))}
                        <div ref={terminalEndRef} />
                    </div>
                    <div className="terminal-input-area">
                        <span className="prompt-label">#</span>
                        <input 
                            type="text" 
                            value={shellCmd}
                            onChange={(e) => setShellCmd(e.target.value)}
                            onKeyDown={handleShellKeyDown}
                            placeholder="Enter command..."
                            autoFocus
                        />
                    </div>
                </div>
            )}

            {activeTab === 'software' && (
                <div className="tab-content fade-in">
                    <div className="software-header">
                        <div className="sw-icon"><Package size={32} /></div>
                        <div>
                            <h4>Software Inventory</h4>
                            <p>Scan system for installed packages (DEB, RPM, Pacman, Apps).</p>
                        </div>
                    </div>
                    <button
                        onClick={fetchSoftware}
                        disabled={softwareLoading}
                        className="btn-execute-xdr btn-software"
                    >
                        {softwareLoading ? <i className="fas fa-spinner fa-spin"></i> : <Activity size={16} />} Start Full Scan
                    </button>
                    
                    <div className="software-hint">
                        <p>Results will appear in the Execution History panel on the right once the agent processes the scan.</p>
                    </div>
                </div>
            )}

          </div>

          {/* RIGHT PANEL - History / Results */}
          {activeTab !== 'terminal' && (
            <div className="modal-right-xdr">
                <div className="section-header">
                <Clock size={18} />
                <h4>Results & History</h4>
                </div>
                <div className="command-history-xdr">
                {commands.length === 0 ? (
                    <div className="empty-commands">No activity recorded.</div>
                ) : (
                    commands.map((cmd) => {
                    const cmdId = getCommandId(cmd)
                    const cmdStatus = getCommandStatus(cmd)
                    const cmdPayload = getCommandPayload(cmd)
                    const cmdResultOutput = getCommandResultOutput(cmd)
                    const cmdErrorMessage = getCommandErrorMessage(cmd)
                    const cmdCreatedAt = getCommandCreatedAt(cmd)
                    const cmdType = getCommandType(cmd)

                    // Skip Shell commands in this view if we want to keep them only in terminal tab
                    // But maybe user wants to see everything here. Let's keep everything for audit.

                    let statusClass = 'status-pending'
                    if (cmdStatus === 'COMPLETED') statusClass = 'status-completed'
                    else if (cmdStatus === 'ERROR') statusClass = 'status-error'
                    else if (cmdStatus === 'SENT') statusClass = 'status-sent'

                    let resultHtml = ''
                    if (cmdResultOutput) {
                        if (cmdType === 'OSQUERY') {
                            try {
                                const json = JSON.parse(cmdResultOutput)
                                resultHtml = JSON.stringify(json, null, 2)
                            } catch (e) {
                                resultHtml = cmdResultOutput
                            }
                        } else {
                            resultHtml = cmdResultOutput
                        }
                        resultHtml = DOMPurify.sanitize(resultHtml, { ALLOWED_TAGS: [] })
                    }

                    return (
                        <div key={cmdId} className="command-card-xdr">
                        <div className="command-header-xdr">
                            <div className="command-status">
                            <span className={`status-badge-xdr ${statusClass}`}>
                                {cmdStatus}
                            </span>
                            <span className="command-type-badge">{cmdType}</span>
                            </div>
                            <span className="command-time">
                            {cmdCreatedAt ? new Date(cmdCreatedAt).toLocaleTimeString() : ''}
                            </span>
                        </div>
                        <div className="command-payload-xdr">
                            <code>{cmdPayload}</code>
                        </div>
                        {cmdResultOutput && (
                            <pre className="command-output-xdr" dangerouslySetInnerHTML={{ __html: resultHtml }}></pre>
                        )}
                        {cmdErrorMessage && (
                            <div className="command-error-xdr">
                            <i className="fas fa-exclamation-triangle"></i>
                            {DOMPurify.sanitize(cmdErrorMessage, { ALLOWED_TAGS: [] })}
                            </div>
                        )}
                        </div>
                    )
                    })
                )}
                </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
