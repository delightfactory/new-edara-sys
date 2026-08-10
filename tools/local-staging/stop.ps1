$ErrorActionPreference = 'Stop'
$containerName = 'edara-staging-db'

docker stop $containerName | Out-Null
Write-Output "Stopped $containerName. Persistent data was preserved."
