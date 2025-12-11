-- Drop indexes
DROP INDEX IF EXISTS idx_command_models_created_at;
DROP INDEX IF EXISTS idx_command_models_agent_status;
DROP INDEX IF EXISTS idx_agent_models_group;
DROP INDEX IF EXISTS idx_agent_models_status;
DROP INDEX IF EXISTS idx_agent_models_last_seen;

-- Drop tables
DROP TABLE IF EXISTS command_models;
DROP TABLE IF EXISTS agent_models;

