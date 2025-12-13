import { useState, useEffect } from 'react'
import axios from 'axios'
import { AlertCircle, User, Clock, CheckCircle, Plus, Filter, MessageSquare, X, LayoutGrid, List as ListIcon } from 'lucide-react'
import { useAuth } from '../auth/AuthContext'
import './Incidents.css'

interface Incident {
    id: string
    title: string
    description: string
    severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL'
    status: 'OPEN' | 'ASSIGNED' | 'RESOLVED' | 'CLOSED'
    assigned_to: string
    created_at: string
}

interface Comment {
    id: string
    author: string
    content: string
    created_at: string
}

export default function Incidents() {
    const { user } = useAuth()
    const [incidents, setIncidents] = useState<Incident[]>([])
    const [showNewModal, setShowNewModal] = useState(false)
    const [selectedIncident, setSelectedIncident] = useState<Incident | null>(null)
    const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid')
    
    // New Incident State
    const [newTitle, setNewTitle] = useState('')
    const [newDesc, setNewDesc] = useState('')
    const [newSeverity, setNewSeverity] = useState('MEDIUM')
    
    // Filter State
    const [filterStatus, setFilterStatus] = useState('ALL')

    // Comments State
    const [comments, setComments] = useState<Comment[]>([])
    const [newComment, setNewComment] = useState('')

    const currentUser = user?.username || "Admin" 

    const fetchIncidents = async () => {
        try {
            const res = await axios.get<Incident[]>('/api/incidents')
            if (res.data && res.data.length > 0) {
                setIncidents(res.data)
            } else {
                // DEMO DATA if DB is empty
                setIncidents([
                    {
                        id: 'demo-1',
                        title: 'Suspicious PowerShell Execution',
                        description: 'Detected encoded PowerShell command execution on workstation HR-02. Potential Cobalt Strike beacon.',
                        severity: 'CRITICAL',
                        status: 'OPEN',
                        assigned_to: '',
                        created_at: new Date().toISOString()
                    },
                    {
                        id: 'demo-2',
                        title: 'Unexpected Sudo Access',
                        description: 'User "guest" attempted sudo access on DB-PROD-01. Access denied but event logged.',
                        severity: 'HIGH',
                        status: 'ASSIGNED',
                        assigned_to: 'x0g',
                        created_at: new Date(Date.now() - 3600000).toISOString()
                    },
                    {
                        id: 'demo-3',
                        title: 'New Service Installed',
                        description: 'Service "UpdaterXYZ" installed on FILE-SRV-03. Unsigned binary.',
                        severity: 'MEDIUM',
                        status: 'RESOLVED',
                        assigned_to: 'Admin',
                        created_at: new Date(Date.now() - 86400000).toISOString()
                    }
                ])
            }
        } catch (e) {
            console.error(e)
        }
    }

    const fetchComments = async (incidentId: string) => {
        try {
            const res = await axios.get<Comment[]>(`/api/incidents/${incidentId}/comments`)
            setComments(res.data)
        } catch (e) {
            console.error(e)
        }
    }

    useEffect(() => {
        fetchIncidents()
        const interval = setInterval(fetchIncidents, 5000)
        return () => clearInterval(interval)
    }, [])

    useEffect(() => {
        if (selectedIncident) {
            fetchComments(selectedIncident.id)
            const interval = setInterval(() => fetchComments(selectedIncident.id), 3000)
            return () => clearInterval(interval)
        }
    }, [selectedIncident])

    const createIncident = async () => {
        if (!newTitle.trim() || !newDesc.trim()) return
        try {
            await axios.post('/api/incidents', {
                title: newTitle,
                description: newDesc,
                severity: newSeverity
            })
            setShowNewModal(false)
            setNewTitle('')
            setNewDesc('')
            fetchIncidents()
        } catch (e) {
            alert('Failed to create incident')
        }
    }

    const updateStatus = async (id: string, status: string, assignedTo: string) => {
        try {
            await axios.put(`/api/incidents/${id}`, {
                assigned_to: assignedTo,
                status: status
            })
            fetchIncidents()
            if (selectedIncident && selectedIncident.id === id) {
                setSelectedIncident({ ...selectedIncident, status: status as any, assigned_to: assignedTo })
            }
        } catch (e) {
            console.error(e)
        }
    }

    const addComment = async () => {
        if (!newComment.trim() || !selectedIncident) return
        try {
            await axios.post(`/api/incidents/${selectedIncident.id}/comments`, {
                author: currentUser,
                content: newComment
            })
            setNewComment('')
            fetchComments(selectedIncident.id)
        } catch (e) {
            console.error(e)
        }
    }

    const filteredIncidents = filterStatus === 'ALL' 
        ? incidents 
        : incidents.filter(i => i.status === filterStatus)

    return (
        <div className="incidents-container">
            <div className="incidents-header">
                <div>
                    <h1>Incident Response</h1>
                    <p className="subtitle">Track and resolve security alerts</p>
                </div>
                <div style={{display: 'flex', gap: '1rem'}}>
                    <div className="view-switcher">
                        <button className={`switch-btn ${viewMode === 'grid' ? 'active' : ''}`} onClick={() => setViewMode('grid')}>
                            <LayoutGrid size={18} />
                        </button>
                        <button className={`switch-btn ${viewMode === 'list' ? 'active' : ''}`} onClick={() => setViewMode('list')}>
                            <ListIcon size={18} />
                        </button>
                    </div>
                    <button className="btn-primary-pink" onClick={() => setShowNewModal(true)}>
                        <Plus size={18} /> New Incident
                    </button>
                </div>
            </div>

            <div className="incidents-filters">
                <button className={`filter-btn ${filterStatus === 'ALL' ? 'active' : ''}`} onClick={() => setFilterStatus('ALL')}>All</button>
                <button className={`filter-btn ${filterStatus === 'OPEN' ? 'active' : ''}`} onClick={() => setFilterStatus('OPEN')}>Open</button>
                <button className={`filter-btn ${filterStatus === 'ASSIGNED' ? 'active' : ''}`} onClick={() => setFilterStatus('ASSIGNED')}>Assigned</button>
                <button className={`filter-btn ${filterStatus === 'RESOLVED' ? 'active' : ''}`} onClick={() => setFilterStatus('RESOLVED')}>Resolved</button>
            </div>

            {filteredIncidents.length === 0 ? (
                <div className="empty-state">
                    <CheckCircle size={48} color="#48bb78" />
                    <p>No incidents found.</p>
                </div>
            ) : viewMode === 'grid' ? (
                <div className="incidents-grid">
                    {filteredIncidents.map(inc => (
                        <div key={inc.id} className={`incident-card border-${inc.severity.toLowerCase()}`} onClick={() => setSelectedIncident(inc)}>
                            <div className="incident-top">
                                <div className="incident-severity-badge">
                                    {inc.severity}
                                </div>
                                <div className={`incident-status ${inc.status.toLowerCase()}`}>
                                    {inc.status}
                                </div>
                            </div>
                            
                            <h3 className="incident-title">{inc.title}</h3>
                            <p className="incident-desc">{inc.description}</p>
                            
                            <div className="incident-meta">
                                <div className="meta-item">
                                    <Clock size={14} /> 
                                    {new Date(inc.created_at).toLocaleString()}
                                </div>
                                <div className="meta-item">
                                    <User size={14} /> 
                                    {inc.assigned_to || 'Unassigned'}
                                </div>
                            </div>

                            <div className="incident-actions" onClick={e => e.stopPropagation()}>
                                {inc.status === 'OPEN' && (
                                    <button className="btn-action btn-assign" onClick={() => updateStatus(inc.id, 'ASSIGNED', currentUser)}>
                                        Assign
                                    </button>
                                )}
                                {inc.status !== 'RESOLVED' && (
                                    <button className="btn-action btn-resolve" onClick={() => updateStatus(inc.id, 'RESOLVED', inc.assigned_to)}>
                                        Resolve
                                    </button>
                                )}
                            </div>
                        </div>
                    ))}
                </div>
            ) : (
                <div className="incidents-list-view">
                    <table className="incidents-table">
                        <thead>
                            <tr>
                                <th>Severity</th>
                                <th>Status</th>
                                <th>Title</th>
                                <th>Assigned To</th>
                                <th>Date</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            {filteredIncidents.map(inc => (
                                <tr key={inc.id} onClick={() => setSelectedIncident(inc)} className={`border-left-${inc.severity.toLowerCase()}`}>
                                    <td><span className="incident-severity-badge">{inc.severity}</span></td>
                                    <td><span className={`incident-status ${inc.status.toLowerCase()}`}>{inc.status}</span></td>
                                    <td className="td-title">{inc.title}</td>
                                    <td>{inc.assigned_to || '-'}</td>
                                    <td>{new Date(inc.created_at).toLocaleDateString()}</td>
                                    <td onClick={e => e.stopPropagation()}>
                                        {inc.status === 'OPEN' && (
                                            <button className="btn-small-assign" onClick={() => updateStatus(inc.id, 'ASSIGNED', currentUser)}>Assign</button>
                                        )}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}

            {/* CREATE MODAL */}
            {showNewModal && (
                <div className="modal-overlay-xdr" onClick={() => setShowNewModal(false)}>
                    <div className="modal-content-xdr incident-modal" onClick={e => e.stopPropagation()}>
                        <div className="modal-header-xdr">
                            <h3>Create New Incident</h3>
                            <button className="close-btn-xdr" onClick={() => setShowNewModal(false)}>×</button>
                        </div>
                        <div className="modal-body-xdr incident-form">
                            <label>Title</label>
                            <input 
                                type="text" 
                                className="input-field" 
                                value={newTitle}
                                onChange={e => setNewTitle(e.target.value)} 
                                placeholder="e.g., Suspicious Shell Activity"
                            />
                            
                            <label>Severity</label>
                            <select 
                                className="input-field"
                                value={newSeverity}
                                onChange={e => setNewSeverity(e.target.value)}
                            >
                                <option value="LOW">Low</option>
                                <option value="MEDIUM">Medium</option>
                                <option value="HIGH">High</option>
                                <option value="CRITICAL">Critical</option>
                            </select>

                            <label>Description</label>
                            <textarea 
                                className="input-field" 
                                rows={5}
                                value={newDesc}
                                onChange={e => setNewDesc(e.target.value)} 
                                placeholder="Describe the detected activity..."
                            />

                            <button className="btn-primary-pink" onClick={createIncident}>
                                Create Incident
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {/* DETAIL MODAL (Same as before) */}
            {selectedIncident && (
                <div className="modal-overlay-xdr" onClick={() => setSelectedIncident(null)}>
                    <div className="modal-content-xdr incident-modal" onClick={e => e.stopPropagation()} style={{maxWidth: '1000px'}}>
                        <div className="modal-header-xdr">
                            <h3>{selectedIncident.title}</h3>
                            <button className="close-btn-xdr" onClick={() => setSelectedIncident(null)}>×</button>
                        </div>
                        <div className="modal-body-xdr incident-detail-layout">
                            <div className="detail-left">
                                <div className="incident-meta" style={{marginBottom: '2rem'}}>
                                    <span className={`incident-severity-badge`}>{selectedIncident.severity}</span>
                                    <span className={`incident-status ${selectedIncident.status.toLowerCase()}`}>{selectedIncident.status}</span>
                                    <span><User size={14}/> {selectedIncident.assigned_to || 'Unassigned'}</span>
                                </div>
                                
                                <h4>Description</h4>
                                <div className="detail-desc">{selectedIncident.description}</div>

                                <div className="comments-section">
                                    <h4>Discussion</h4>
                                    <div className="comments-list">
                                        {comments.map(c => (
                                            <div key={c.id} className="comment">
                                                <div className="comment-header">
                                                    <span className="comment-author">{c.author}</span>
                                                    <span>{new Date(c.created_at).toLocaleString()}</span>
                                                </div>
                                                <div className="comment-body">{c.content}</div>
                                            </div>
                                        ))}
                                    </div>
                                    <div className="comment-input-area">
                                        <textarea 
                                            className="input-field" 
                                            rows={3} 
                                            placeholder="Leave a comment..."
                                            value={newComment}
                                            onChange={e => setNewComment(e.target.value)}
                                        />
                                        <button className="btn-comment" onClick={addComment}>Comment</button>
                                    </div>
                                </div>
                            </div>
                            
                            <div className="detail-right">
                                <h4>Actions</h4>
                                <div style={{display: 'flex', flexDirection: 'column', gap: '1rem', marginTop: '1rem'}}>
                                    {selectedIncident.status === 'OPEN' && (
                                        <button className="btn-primary-pink" onClick={() => updateStatus(selectedIncident.id, 'ASSIGNED', currentUser)}>
                                            Assign to Me
                                        </button>
                                    )}
                                    {selectedIncident.assigned_to === currentUser && selectedIncident.status !== 'RESOLVED' && (
                                        <button className="btn-action btn-unassign" onClick={() => updateStatus(selectedIncident.id, 'OPEN', '')}>
                                            Unassign Me
                                        </button>
                                    )}
                                    {selectedIncident.status !== 'RESOLVED' && (
                                        <button className="btn-action btn-resolve" onClick={() => updateStatus(selectedIncident.id, 'RESOLVED', selectedIncident.assigned_to)}>
                                            Resolve Incident
                                        </button>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    )
}
