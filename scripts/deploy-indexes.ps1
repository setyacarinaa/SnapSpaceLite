<#
Deploy Firestore indexes script
Usage:
  .\deploy-indexes.ps1 -ProjectId YOUR_PROJECT_ID
  OR
  .\deploy-indexes.ps1            # interactive if firebase already selected

What it does:
 - Checks that `firebase` CLI is available
 - Optionally switches to provided project id
 - Runs: firebase deploy --only firestore:indexes [--project <id>]

Note: This script does not install firebase-tools. If missing, follow instructions printed.
#>
param(
    [string]$ProjectId
)

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Ensure script runs from repo root if possible
try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Set-Location -LiteralPath (Resolve-Path "$scriptDir/..") | Out-Null
} catch {
    # ignore
}

Write-Info "Checking for Firebase CLI..."
$firebaseCmd = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebaseCmd) {
    Write-Err "Firebase CLI not found. Install with: npm install -g firebase-tools"
    Write-Host "Or visit https://firebase.google.com/docs/cli" -ForegroundColor Yellow
    exit 1
}

if (Test-Path .\firestore.indexes.json) {
    Write-Info "Found firestore.indexes.json"
} else {
    Write-Err "firestore.indexes.json not found in repository root. Ensure the file exists."
    exit 2
}

if ($ProjectId) {
    Write-Info "Setting firebase project to '$ProjectId'"
    & firebase use $ProjectId 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Could not set project using 'firebase use'. Trying with --project flag on deploy."
    } else {
        Write-Ok "Active project set to '$ProjectId'"
    }
}

# Build deploy command
if ($ProjectId) {
    $cmd = "firebase deploy --only firestore:indexes --project $ProjectId"
} else {
    $cmd = "firebase deploy --only firestore:indexes"
}

Write-Info "Running: $cmd"
Write-Info "This may take a few moments while Firestore builds the index in the console."

# Execute
$proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile -Command $cmd" -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -eq 0) {
    Write-Ok "Deploy command finished successfully."
    Write-Host "Open Firebase Console -> Firestore -> Indexes to monitor build status." -ForegroundColor Cyan
    exit 0
} else {
    Write-Err "Deploy command failed with exit code $($proc.ExitCode)."
    Write-Host "Try running the command manually to see details:" -ForegroundColor Yellow
    Write-Host "  $cmd" -ForegroundColor Gray
    exit $proc.ExitCode
}
