-- ===========================================================================
-- ProxySQL runtime configuration (loaded by startup.sh on every boot).
-- Topology: one primary (writer) + one replica (reader).
-- ===========================================================================

-- --- Backend servers -------------------------------------------------------
-- Both are registered in the writer hostgroup (10). ProxySQL's monitor then
-- reads each server's read_only flag and, using the replication_hostgroups
-- mapping below, automatically moves the read-only replica into the reader
-- hostgroup (20). This also gives automatic failover if roles change.
INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (10, 'mysql-primary', 3306);
INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (10, 'mysql-replica', 3306);

-- --- Automatic read/write split by read_only flag --------------------------
INSERT INTO mysql_replication_hostgroups (writer_hostgroup, reader_hostgroup, comment)
VALUES (10, 20, 'primary=writer(10), replica=reader(20)');

-- --- Query routing rules ---------------------------------------------------
-- Rules are evaluated by rule_id order.
--  1) "SELECT ... FOR UPDATE" must read the primary -> hostgroup 10.
--  2) Any other SELECT -> reader hostgroup 20.
-- Everything else falls through to the user's default_hostgroup (10 = writer).
INSERT INTO mysql_query_rules (rule_id, active, match_digest, destination_hostgroup, apply)
VALUES (1, 1, '^SELECT.*FOR UPDATE', 10, 1);
INSERT INTO mysql_query_rules (rule_id, active, match_digest, destination_hostgroup, apply)
VALUES (2, 1, '^SELECT', 20, 1);

-- --- Monitor tuning --------------------------------------------------------
UPDATE global_variables SET variable_value='2000' WHERE variable_name='mysql-monitor_connect_interval';
UPDATE global_variables SET variable_value='2000' WHERE variable_name='mysql-monitor_ping_interval';
UPDATE global_variables SET variable_value='2000' WHERE variable_name='mysql-monitor_read_only_interval';

-- --- Persist -------------------------------------------------------------
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;
