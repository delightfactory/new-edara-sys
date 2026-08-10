param(
  [Parameter(Mandatory = $true)]
  [string]$MigrationFile
)

$ErrorActionPreference = 'Stop'
$containerName = 'edara-staging-db'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$migrationsRoot = (Resolve-Path (Join-Path $repoRoot 'supabase\migrations')).Path
$resolvedMigration = (Resolve-Path -LiteralPath $MigrationFile).Path

if (-not $resolvedMigration.StartsWith($migrationsRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) {
  throw 'MigrationFile must be inside this repository''s supabase/migrations directory.'
}

if ((docker inspect $containerName --format '{{.State.Running}}') -ne 'true') {
  throw "Local staging container '$containerName' is not running."
}

Get-Content -Raw -LiteralPath $resolvedMigration |
  docker exec -i $containerName psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres

if ($LASTEXITCODE -ne 0) {
  throw "Migration failed with exit code $LASTEXITCODE."
}

Write-Output "Applied locally: $resolvedMigration"
