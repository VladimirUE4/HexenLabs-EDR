import { useEffect, useState } from 'react';
import axios from 'axios';
import { 
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend 
} from 'recharts';
import { Users, Activity, AlertTriangle, WifiOff } from 'lucide-react';
import './DashboardNew.css';
import { Agent, getAgentStatus, getAgentOsType } from '../App';

interface DashboardProps {
  agents: Agent[];
}

export default function Dashboard({ agents }: DashboardProps) {
  const [stats, setStats] = useState({
    total: 0,
    online: 0,
    offline: 0,
    alerts: 0
  });

  // Derived state for OS distribution
  const osData = [
    { name: 'Linux', value: agents.filter(a => getAgentOsType(a) === 'linux').length },
    { name: 'Windows', value: agents.filter(a => getAgentOsType(a) === 'windows').length },
    { name: 'macOS', value: agents.filter(a => getAgentOsType(a) === 'darwin' || getAgentOsType(a) === 'macos').length },
  ].filter(d => d.value > 0);

  const COLORS = ['rgb(248, 113, 113)', '#fca5a5', '#fecaca'];

  // Mock data for activity (would come from backend history normally)
  const activityData = [
    { name: '00:00', queries: 40, alerts: 2 },
    { name: '04:00', queries: 30, alerts: 1 },
    { name: '08:00', queries: 120, alerts: 5 },
    { name: '12:00', queries: 180, alerts: 8 },
    { name: '16:00', queries: 150, alerts: 4 },
    { name: '20:00', queries: 90, alerts: 3 },
    { name: '23:59', queries: 50, alerts: 2 },
  ];

  useEffect(() => {
    const onlineCount = agents.filter(a => getAgentStatus(a) === 'ONLINE').length;
    setStats({
      total: agents.length,
      online: onlineCount,
      offline: agents.length - onlineCount,
      alerts: 0 // Mock for now
    });
  }, [agents]);

  return (
    <div className="dashboard-container">
      <div className="dashboard-header">
        <h1>Security Overview</h1>
      </div>

      <div className="dashboard-stats-grid">
        <div className="stat-card">
          <div className="stat-content">
            <h3>Total Agents</h3>
            <div className="value">{stats.total}</div>
          </div>
          <div className="stat-icon agents">
            <Users size={24} />
          </div>
        </div>

        <div className="stat-card">
          <div className="stat-content">
            <h3>Online</h3>
            <div className="value">{stats.online}</div>
          </div>
          <div className="stat-icon online">
            <Activity size={24} />
          </div>
        </div>

        <div className="stat-card">
          <div className="stat-content">
            <h3>Offline</h3>
            <div className="value">{stats.offline}</div>
          </div>
          <div className="stat-icon offline">
            <WifiOff size={24} />
          </div>
        </div>

        <div className="stat-card">
          <div className="stat-content">
            <h3>Active Alerts</h3>
            <div className="value">{stats.alerts}</div>
          </div>
          <div className="stat-icon alerts">
            <AlertTriangle size={24} />
          </div>
        </div>
      </div>

      <div className="charts-grid">
        <div className="chart-card">
          <div className="chart-header">
            <h3>Agent Activity (24h)</h3>
          </div>
          <div style={{ height: 300 }}>
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={activityData}>
                <defs>
                  <linearGradient id="colorQueries" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="rgb(248, 113, 113)" stopOpacity={0.8}/>
                    <stop offset="95%" stopColor="rgb(248, 113, 113)" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#333" />
                <XAxis dataKey="name" stroke="#888" />
                <YAxis stroke="#888" />
                <Tooltip 
                  contentStyle={{ backgroundColor: '#2d2d2d', border: '1px solid #444' }}
                  itemStyle={{ color: '#fff' }}
                />
                <Area type="monotone" dataKey="queries" stroke="rgb(248, 113, 113)" fillOpacity={1} fill="url(#colorQueries)" />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="chart-card">
          <div className="chart-header">
            <h3>OS Distribution</h3>
          </div>
          <div style={{ height: 300 }}>
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie
                  data={osData}
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={100}
                  fill="#8884d8"
                  paddingAngle={5}
                  dataKey="value"
                >
                  {osData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip 
                   contentStyle={{ backgroundColor: '#2d2d2d', border: '1px solid #444' }}
                   itemStyle={{ color: '#fff' }}
                />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>
    </div>
  );
}
