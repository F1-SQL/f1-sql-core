#!/usr/bin/env bash
set -euo pipefail

: "${F1SQL_SQLSERVER_PASSWORD:?F1SQL_SQLSERVER_PASSWORD must be set}"
: "${F1SQL_BACKUP_INPUT:?F1SQL_BACKUP_INPUT must be set}"
container_name="${F1SQL_SQLSERVER_CONTAINER:-f1sql-sqlserver2022}"
image="${F1SQL_SQLSERVER_IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"
core_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
database_root="$core_root/database"
sqlcmd_path="/opt/mssql-tools18/bin/sqlcmd"

cleanup() { docker rm -f "$container_name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker rm -f "$container_name" >/dev/null 2>&1 || true
docker run --name "$container_name" -e ACCEPT_EULA=Y -e MSSQL_PID=Developer \
  -e MSSQL_SA_PASSWORD="$F1SQL_SQLSERVER_PASSWORD" -p "${F1SQL_SQLSERVER_PORT:-14334}:1433" \
  -d "$image" >/dev/null

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

docker cp "$F1SQL_BACKUP_INPUT" "$container_name:/tmp/F1SqlPhase5.bak"
docker exec -u 0 "$container_name" chmod 644 /tmp/F1SqlPhase5.bak
docker cp "$database_root/tests/phase5_release_smoke.sql" "$container_name:/tmp/phase5_release_smoke.sql"
sqlcmd -d master -b -Q "RESTORE VERIFYONLY FROM DISK = N'/tmp/F1SqlPhase5.bak' WITH CHECKSUM;"
sqlcmd -d master -b -Q "RESTORE DATABASE F1SqlPhase5Restore FROM DISK = N'/tmp/F1SqlPhase5.bak' WITH MOVE N'F1SqlPhase5' TO N'/var/opt/mssql/data/F1SqlPhase5Restore.mdf', MOVE N'F1SqlPhase5_log' TO N'/var/opt/mssql/data/F1SqlPhase5Restore_log.ldf', CHECKSUM, RECOVERY; DBCC CHECKDB(N'F1SqlPhase5Restore') WITH NO_INFOMSGS, ALL_ERRORMSGS;"
sqlcmd -d F1SqlPhase5Restore -b -i /tmp/phase5_release_smoke.sql
