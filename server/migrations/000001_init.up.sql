-- Create agents table
CREATE TABLE IF NOT EXISTS agent_models (
    id VARCHAR(255) PRIMARY KEY,
    hostname VARCHAR(255) NOT NULL,
    os_type VARCHAR(50) NOT NULL,
    os_version VARCHAR(255),
    ip_address VARCHAR(50),
    last_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'OFFLINE',
    agent_name VARCHAR(255),
    agent_group VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create index on last_seen for status queries
CREATE INDEX IF NOT EXISTS idx_agent_models_last_seen ON agent_models(last_seen);

-- Create index on status for filtering
CREATE INDEX IF NOT EXISTS idx_agent_models_status ON agent_models(status);

-- Create index on agent_group for grouping
CREATE INDEX IF NOT EXISTS idx_agent_models_group ON agent_models(agent_group);

-- Create commands table
CREATE TABLE IF NOT EXISTS command_models (
    id VARCHAR(255) PRIMARY KEY,
    agent_id VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL,
    payload TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    result_output TEXT,
    error_message TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    deleted_at TIMESTAMP,
    FOREIGN KEY (agent_id) REFERENCES agent_models(id) ON DELETE CASCADE
);

-- Create composite index for command queries
CREATE INDEX IF NOT EXISTS idx_command_models_agent_status ON command_models(agent_id, status, created_at);

-- Create index on created_at for ordering
CREATE INDEX IF NOT EXISTS idx_command_models_created_at ON command_models(created_at DESC);

