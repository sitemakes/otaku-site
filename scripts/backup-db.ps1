# Dump the shared Supabase database (roles, schema, data) into a dated folder and
# delete local backups older than 30 days (privacy policy: backups are kept at most 30 days).
# Needs Docker Desktop running and Node.js (uses `npx supabase`). See docs/backup-restore-runbook.md.
#
# Usage (PowerShell):
#   $env:OTAKU_DB_URL = "<Session pooler connection string with the DB password>"
#   powershell -ExecutionPolicy Bypass -File scripts\backup-db.ps1
#   Remove-Item Env:OTAKU_DB_URL
#
# Never commit the connection string or the dump files: they contain personal data of
# OTAKU LIVE and student-chat users.

param(
  [string]$BackupRoot = (Join-Path $env:USERPROFILE "otaku-db-backups"),
  [int]$KeepDays = 30
)

$ErrorActionPreference = "Stop"

if (-not $env:OTAKU_DB_URL) {
  Write-Error "Set `$env:OTAKU_DB_URL to the Session pooler connection string first."
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ($BackupRoot.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
  Write-Error "BackupRoot must be outside the repository: $BackupRoot"
}
docker info *> $null
if ($LASTEXITCODE -ne 0) { Write-Error "Docker Desktop is not running." }

$dir = Join-Path $BackupRoot (Get-Date -Format "yyyy-MM-dd_HHmm")
New-Item -ItemType Directory -Force $dir | Out-Null

npx --yes supabase db dump --db-url $env:OTAKU_DB_URL -f (Join-Path $dir "roles.sql") --role-only
if ($LASTEXITCODE -ne 0) { Write-Error "roles dump failed" }
npx --yes supabase db dump --db-url $env:OTAKU_DB_URL -f (Join-Path $dir "schema.sql")
if ($LASTEXITCODE -ne 0) { Write-Error "schema dump failed" }
npx --yes supabase db dump --db-url $env:OTAKU_DB_URL -f (Join-Path $dir "data.sql") --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"
if ($LASTEXITCODE -ne 0) { Write-Error "data dump failed" }

foreach ($name in "roles.sql", "schema.sql", "data.sql") {
  $file = Get-Item (Join-Path $dir $name)
  if ($file.Length -eq 0) { Write-Error "$name is empty" }
}
$tables = (Select-String -Path (Join-Path $dir "data.sql") -Pattern '^COPY "public"\."otaku_' | Measure-Object).Count
Write-Output "Saved to $dir ($tables OTAKU LIVE tables in data.sql)"

Get-ChildItem $BackupRoot -Directory |
  Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$KeepDays) } |
  ForEach-Object {
    Write-Output "Removing expired backup $($_.FullName)"
    Remove-Item -Recurse -Force $_.FullName
  }
