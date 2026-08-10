$ErrorActionPreference = 'Stop'
$containerName = 'edara-staging-db'

docker start $containerName | Out-Null
docker exec $containerName pg_isready -U supabase_admin -d postgres
