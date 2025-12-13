import { useState, useEffect } from 'react'
import axios from 'axios'
import { Agent, getAgentId, getAgentHostname, getAgentIpAddress, getAgentOsType, getAgentStatus, getAgentLastSeen } from '../App'
import AgentModal from './AgentModal'
import { Monitor, Server, Clock, Search, MoreHorizontal, Terminal, Activity, CheckSquare, Square, ShieldCheck } from 'lucide-react'
import nacl from 'tweetnacl'
import { encode as encodeHex } from 'tweetnacl-util'
import './AgentList.css'

// ADMIN PRIVATE KEY (For Demo Only)
const ADMIN_PRIV_KEY_HEX = "2f7d04aff1982f68b8f8643f55c61ae94722cb49899d20a4d50f4787dd80d938fe3012be0c173015cc27f25c8c52b7a62da031600bde3b062439bd25fb6df497";

const hexToBytes = (hex: string): Uint8Array => {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
    }
    return bytes;
}

const bytesToHex = (bytes: Uint8Array): string => {
    return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
}

const signPayload = (payload: string): string => {
    const privKey = hexToBytes(ADMIN_PRIV_KEY_HEX);
    const msgBytes = new TextEncoder().encode(payload);
    const signature = nacl.sign.detached(msgBytes, privKey);
    return bytesToHex(signature);
}

export default function AgentList() {
  const [agents, setAgents] = useState<Agent[]>([])
  const [selectedAgent, setSelectedAgent] = useState<Agent | null>(null)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [searchTerm, setSearchTerm] = useState('')
  const [showBulkAction, setShowBulkAction] = useState(false)
  const [bulkCommand, setBulkCommand] = useState('')
  const [bulkLoading, setBulkLoading] = useState(false)
  const [bulkResults, setBulkResults] = useState<{agentId: string, status: string}[]>([])

  const fetchAgents = async () => {
    try {
      const res = await axios.get<Agent[]>('/api/agents')
      setAgents(res.data)
    } catch (err) {
      console.error('Failed to fetch agents:', err)
    }
  }

  useEffect(() => {
    fetchAgents()
    const interval = setInterval(fetchAgents, 5000)
    return () => clearInterval(interval)
  }, [])

  const toggleSelection = (id: string) => {
      const newSet = new Set(selectedIds)
      if (newSet.has(id)) {
          newSet.delete(id)
      } else {
          newSet.add(id)
      }
      setSelectedIds(newSet)
  }

  const toggleSelectAll = () => {
      if (selectedIds.size === filteredAgents.length) {
          setSelectedIds(new Set())
      } else {
          setSelectedIds(new Set(filteredAgents.map(a => getAgentId(a))))
      }
  }

  const executeBulkCommand = async () => {
      if (!bulkCommand.trim() || selectedIds.size === 0) return
      
      setBulkLoading(true)
      setBulkResults([])
      try {
          // Sign payload once
          const signature = signPayload(bulkCommand);

          const promises = Array.from(selectedIds).map(async (id) => {
             try {
                 await axios.post(`/api/agents/${id}/osquery`, { 
                     query: bulkCommand, 
                     type: 'SHELL',
                     signature: signature
                 })
                 return { agentId: id, status: 'SENT' }
             } catch (e) {
                 return { agentId: id, status: 'FAILED' }
             }
          })
          
          const results = await Promise.all(promises)
          setBulkResults(results)
          setBulkCommand('')
          // Don't close immediately, show results
      } catch (e) {
          console.error(e)
          alert("Error executing bulk command")
      } finally {
          setBulkLoading(false)
      }
  }

  const closeBulkModal = () => {
      setShowBulkAction(false)
      setBulkResults([])
      setBulkCommand('')
      setSelectedIds(new Set())
  }

  const filteredAgents = agents.filter(agent => 
    getAgentHostname(agent).toLowerCase().includes(searchTerm.toLowerCase()) ||
    getAgentId(agent).toLowerCase().includes(searchTerm.toLowerCase())
  )

  return (
    <div className="agent-list-container">
      
      {/* HEADER & ACTIONS */}
      <div className="list-header">
        <div className="search-bar">
            <Search size={18} />
            <input 
                type="text" 
                placeholder="Search endpoints..." 
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
            />
        </div>
        
        {selectedIds.size > 0 && (
            <div className="bulk-actions fade-in">
                <span>{selectedIds.size} selected</span>
                <button className="btn-bulk" onClick={() => setShowBulkAction(true)}>
                    <Terminal size={16} /> Run Command
                </button>
            </div>
        )}
      </div>

      {/* AGENT TABLE */}
      <div className="agents-table-wrapper">
        <table className="agents-table">
            <thead>
                <tr>
                    <th className="th-check" onClick={toggleSelectAll}>
                        {selectedIds.size > 0 && selectedIds.size === filteredAgents.length ? <CheckSquare size={18} /> : <Square size={18} />}
                    </th>
                    <th>Status</th>
                    <th>Hostname</th>
                    <th>OS</th>
                    <th>IP Address</th>
                    <th>Last Seen</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                {filteredAgents.length === 0 ? (
                    <tr>
                        <td colSpan={7} className="empty-state">No agents found.</td>
                    </tr>
                ) : (
                    filteredAgents.map(agent => {
                        const id = getAgentId(agent)
                        const isSelected = selectedIds.has(id)
                        const status = getAgentStatus(agent)
                        
                        return (
                            <tr key={id} className={isSelected ? 'selected-row' : ''} onClick={() => setSelectedAgent(agent)}>
                                <td className="td-check" onClick={(e) => { e.stopPropagation(); toggleSelection(id); }}>
                                    {isSelected ? <CheckSquare size={18} className="icon-checked" /> : <Square size={18} className="icon-unchecked" />}
                                </td>
                                <td>
                                    <span className={`status-indicator ${status === 'ONLINE' ? 'online' : 'offline'}`}>
                                        {status}
                                    </span>
                                </td>
                                <td className="td-hostname">
                                    <Server size={16} />
                                    {getAgentHostname(agent)}
                                </td>
                                <td className="td-os">
                                    <i className={`fab fa-${getAgentOsType(agent) === 'linux' ? 'linux' : getAgentOsType(agent) === 'windows' ? 'windows' : 'apple'}`}></i>
                                    {getAgentOsType(agent)}
                                </td>
                                <td>{getAgentIpAddress(agent)}</td>
                                <td className="td-time">
                                    <Clock size={14} />
                                    {getAgentLastSeen(agent) ? new Date(getAgentLastSeen(agent)).toLocaleString() : 'Never'}
                                </td>
                                <td onClick={(e) => e.stopPropagation()}>
                                    <button className="btn-icon" onClick={() => setSelectedAgent(agent)}>
                                        <Activity size={18} />
                                    </button>
                                </td>
                            </tr>
                        )
                    })
                )}
            </tbody>
        </table>
      </div>

      {/* MODALS */}
      {selectedAgent && (
        <AgentModal 
          agent={selectedAgent} 
          onClose={() => setSelectedAgent(null)} 
        />
      )}

      {showBulkAction && (
          <div className="modal-overlay-xdr" onClick={closeBulkModal}>
              <div className="modal-content-xdr bulk-modal" onClick={(e) => e.stopPropagation()}>
                  <div className="modal-header-xdr">
                      <h3>Execute Bulk Command (Secure)</h3>
                      <button className="close-btn-xdr" onClick={closeBulkModal}>×</button>
                  </div>
                  <div className="modal-body-xdr bulk-body">
                      {bulkResults.length === 0 ? (
                        <>
                            <div className="security-notice">
                                <ShieldCheck size={20} color="#48bb78" />
                                <p>Commands are cryptographically signed (Ed25519) before sending.</p>
                            </div>
                            <p>Targeting <strong>{selectedIds.size}</strong> agents.</p>
                            <textarea 
                                className="query-input-xdr terminal-input"
                                value={bulkCommand}
                                onChange={(e) => setBulkCommand(e.target.value)}
                                placeholder="uname -a"
                                rows={5}
                            />
                            <div className="bulk-footer">
                                <button className="btn-execute-xdr btn-terminal" onClick={executeBulkCommand} disabled={bulkLoading}>
                                    {bulkLoading ? 'Signing & Sending...' : 'Execute Securely'}
                                </button>
                            </div>
                        </>
                      ) : (
                          <div className="bulk-results">
                              <h4>Execution Report</h4>
                              <div className="results-list">
                                  {bulkResults.map((res, i) => (
                                      <div key={i} className={`result-item ${res.status.toLowerCase()}`}>
                                          <span className="res-id">{res.agentId}</span>
                                          <span className="res-status">{res.status}</span>
                                      </div>
                                  ))}
                              </div>
                              <button className="btn-execute-xdr" onClick={closeBulkModal} style={{marginTop: '1rem'}}>
                                  Close
                              </button>
                          </div>
                      )}
                  </div>
              </div>
          </div>
      )}
    </div>
  )
}
