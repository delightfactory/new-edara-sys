$ErrorActionPreference = 'Stop'
$containerName = 'edara-staging-db'

$exists = docker ps -a --filter "name=^/$containerName$" --format '{{.Names}}'
if ($exists -ne $containerName) {
  throw "Local staging container '$containerName' does not exist."
}

docker inspect $containerName --format 'Status={{.State.Status}} Restart={{.HostConfig.RestartPolicy.Name}}'
docker port $containerName

if ((docker inspect $containerName --format '{{.State.Running}}') -eq 'true') {
  docker exec $containerName pg_isready -U supabase_admin -d postgres
  docker exec $containerName psql -U supabase_admin -d postgres -P pager=off -c @'
select
  current_database() as database_name,
  version() as postgres_version,
  pg_size_pretty(pg_database_size(current_database())) as database_size;
'@
}
