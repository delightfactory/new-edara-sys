param(
  [Parameter(Mandatory = $true)]
  [string]$BackupFile,

  [switch]$ConfirmReset
)

$ErrorActionPreference = 'Stop'
$containerName = 'edara-staging-db'

if (-not $ConfirmReset) {
  throw 'Reset refused. Pass -ConfirmReset to replace only the local staging database.'
}

$resolvedBackup = (Resolve-Path -LiteralPath $BackupFile).Path
if ([IO.Path]::GetFileName($resolvedBackup) -ne 'full_database.dump') {
  throw 'BackupFile must point to a full_database.dump archive.'
}

if ((docker inspect $containerName --format '{{.State.Running}}') -ne 'true') {
  throw "Local staging container '$containerName' is not running."
}

docker cp $resolvedBackup "${containerName}:/tmp/full_database.dump"
if ($LASTEXITCODE -ne 0) { throw 'Copying the backup into local staging failed.' }

docker exec $containerName psql -v ON_ERROR_STOP=1 -U supabase_admin -d template1 `
  -c 'DROP DATABASE postgres WITH (FORCE);'
if ($LASTEXITCODE -ne 0) { throw 'Dropping the local staging database failed.' }

docker exec $containerName psql -v ON_ERROR_STOP=1 -U supabase_admin -d template1 `
  -c 'CREATE DATABASE postgres WITH TEMPLATE template0 OWNER supabase_admin;'
if ($LASTEXITCODE -ne 0) { throw 'Recreating the local staging database failed.' }

docker exec $containerName pg_restore --exit-on-error --no-owner --no-privileges `
  -U supabase_admin -d postgres /tmp/full_database.dump
if ($LASTEXITCODE -ne 0) { throw 'Restoring the local staging database failed.' }

Write-Output "Local staging was reset from: $resolvedBackup"
