#!/usr/bin/env bash
set -euo pipefail

: "${F1SQL_SQLSERVER_PASSWORD:?F1SQL_SQLSERVER_PASSWORD must be set}"
container_name="${F1SQL_SQLSERVER_CONTAINER:-f1sql-sqlserver2019}"
image="${F1SQL_SQLSERVER_IMAGE:-mcr.microsoft.com/mssql/server:2019-latest}"
database_name="${F1SQL_TEST_DATABASE:-F1SqlPhase5}"
backup_output="${F1SQL_BACKUP_OUTPUT:-}"
load_sql="${F1SQL_LOAD_SQL:-}"
python_bin="${F1SQL_PYTHON:-python3}"
core_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
database_root="$core_root/database"
sqlcmd_path="/opt/mssql-tools18/bin/sqlcmd"

cleanup() {
  docker rm -f "$container_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker rm -f "$container_name" >/dev/null 2>&1 || true
docker run --name "$container_name" \
  -e ACCEPT_EULA=Y -e MSSQL_PID=Developer \
  -e MSSQL_SA_PASSWORD="$F1SQL_SQLSERVER_PASSWORD" \
  -p "${F1SQL_SQLSERVER_PORT:-14333}:1433" -d "$image" >/dev/null

sqlcmd() {
  docker exec "$container_name" "$sqlcmd_path" -S localhost -U sa \
    -P "$F1SQL_SQLSERVER_PASSWORD" -C "$@"
}

for attempt in $(seq 1 60); do
  if sqlcmd -d master -b -Q "SET NOCOUNT ON; SELECT 1;" >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" = 60 ]; then
    docker logs "$container_name"
    echo "SQL Server did not accept sa logins before timeout" >&2
    exit 1
  fi
  sleep 2
done

docker cp "$database_root/schema/v2/0001_metadata.sql" "$container_name:/tmp/0001_metadata.sql"
docker cp "$database_root/schema/v2/0002_core_domain.sql" "$container_name:/tmp/0002_core_domain.sql"
docker cp "$database_root/schema/v2/0003_compatibility_views.sql" "$container_name:/tmp/0003_compatibility_views.sql"
docker cp "$database_root/tests/phase5_integration.sql" "$container_name:/tmp/phase5_integration.sql"
docker cp "$database_root/tests/phase5_fixture_smoke.sql" "$container_name:/tmp/phase5_fixture_smoke.sql"
docker cp "$database_root/tests/phase5_release_smoke.sql" "$container_name:/tmp/phase5_release_smoke.sql"

sqlcmd -d master -b -Q "IF DB_ID(N'$database_name') IS NULL CREATE DATABASE [$database_name];"
for migration in 0001_metadata 0002_core_domain 0003_compatibility_views; do
  sqlcmd -d "$database_name" -b -i "/tmp/${migration}.sql"
done
sqlcmd -d "$database_name" -b -i /tmp/phase5_integration.sql

if [ -n "$load_sql" ]; then
  test -f "$load_sql"
  chmod 644 "$load_sql"
  docker cp "$load_sql" "$container_name:/tmp/f1sql-load.sql"
  sqlcmd -d "$database_name" -b -i /tmp/f1sql-load.sql
else
  fixture_sql="$(mktemp)"
  trap 'rm -f "$fixture_sql"; cleanup' EXIT
  PYTHONPATH="$core_root/src:$core_root/tests" \
    "$python_bin" "$core_root/scripts/render_fixture_load_sql.py" "$fixture_sql"
  chmod 644 "$fixture_sql"
  docker cp "$fixture_sql" "$container_name:/tmp/f1sql-fixture-load.sql"
  sqlcmd -d "$database_name" -b -i /tmp/f1sql-fixture-load.sql
  sqlcmd -d "$database_name" -b -i /tmp/f1sql-fixture-load.sql
  sqlcmd -d "$database_name" -b -i /tmp/phase5_fixture_smoke.sql
fi
sqlcmd -d master -b -Q "DBCC CHECKDB(N'$database_name') WITH NO_INFOMSGS, ALL_ERRORMSGS;"

docker exec "$container_name" sh -lc 'mkdir -p /var/opt/mssql/backup'
sqlcmd -d master -b -Q "BACKUP DATABASE [$database_name] TO DISK = N'/var/opt/mssql/backup/F1SqlPhase5.bak' WITH INIT, COMPRESSION, CHECKSUM, STATS = 10; RESTORE VERIFYONLY FROM DISK = N'/var/opt/mssql/backup/F1SqlPhase5.bak' WITH CHECKSUM;"
sqlcmd -d master -b -Q "IF DB_ID(N'${database_name}Restore') IS NOT NULL BEGIN ALTER DATABASE [${database_name}Restore] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [${database_name}Restore]; END; RESTORE DATABASE [${database_name}Restore] FROM DISK = N'/var/opt/mssql/backup/F1SqlPhase5.bak' WITH MOVE N'F1SqlPhase5' TO N'/var/opt/mssql/data/F1SqlPhase5Restore.mdf', MOVE N'F1SqlPhase5_log' TO N'/var/opt/mssql/data/F1SqlPhase5Restore_log.ldf', CHECKSUM, RECOVERY; DBCC CHECKDB(N'${database_name}Restore') WITH NO_INFOMSGS, ALL_ERRORMSGS;"
sqlcmd -d "${database_name}Restore" -b -i /tmp/phase5_release_smoke.sql

if [ -n "$backup_output" ]; then
  mkdir -p "$(dirname "$backup_output")"
  docker cp "$container_name:/var/opt/mssql/backup/F1SqlPhase5.bak" "$backup_output"
fi
