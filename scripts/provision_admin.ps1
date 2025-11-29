<#
.SYNOPSIS
Interactive helper to provision the System Admin account using the Node admin script.

.DESCRIPTION
Prompts for the service account path, admin email (defaults to the project's configured admin),
and a secure password. It sets the environment variables only for the current PowerShell session
and runs `node .\scripts\create_admin_user.mjs`.

USAGE
Run from project root in PowerShell:
    .\scripts\provision_admin.ps1

#>

function Get-SecurePasswordPlainText {
    param([string]$Prompt = 'Password')
    $secure = Read-Host -AsSecureString -Prompt $Prompt
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        if ($bstr) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

Write-Host 'Provision System Admin helper'

$defaultSa = Join-Path -Path (Get-Location) -ChildPath 'serviceAccountKey.json'
$saPath = Read-Host "Path to service account JSON (leave empty to try $defaultSa)"
if (-not $saPath) { $saPath = $defaultSa }

if (-not (Test-Path $saPath)) {
    Write-Host "Service account not found at: $saPath" -ForegroundColor Yellow
    $useDefault = Read-Host 'Proceed with Application Default Credentials instead? (y/N)'
    if ($useDefault -ne 'y') { Write-Host 'Aborting.'; exit 1 }
}

$defaultAdmin = 'adminsnapspacelite29@gmail.com'
$adminEmail = Read-Host "Admin email (leave empty to use $defaultAdmin)"
if (-not $adminEmail) { $adminEmail = $defaultAdmin }

$adminPassword = Get-SecurePasswordPlainText -Prompt 'Admin password (input hidden)'
if (-not $adminPassword) { Write-Host 'Password is required. Aborting.'; exit 1 }

Write-Host 'Running provisioning script...'

# Set env vars for this session only
$env:GOOGLE_APPLICATION_CREDENTIALS = $saPath
$env:ADMIN_EMAIL = $adminEmail
$env:ADMIN_PASSWORD = $adminPassword

try {
    node .\scripts\create_admin_user.mjs
    $code = $LASTEXITCODE
    if ($code -eq 0) { Write-Host 'Provisioning finished successfully.' -ForegroundColor Green }
    else { Write-Host "Provisioning exited with code $code" -ForegroundColor Red }
} catch {
    Write-Host "Error running node: $_" -ForegroundColor Red
} finally {
    # Clear sensitive env var from session
    Remove-Item env:ADMIN_PASSWORD -ErrorAction SilentlyContinue
}

# Automatic verification step: run verify_admin.mjs to confirm claims and Firestore role
try {
    Write-Host 'Running verification...' -ForegroundColor Cyan
    # pass the email as arg to the verify script
    node .\scripts\verify_admin.mjs $adminEmail
    $vcode = $LASTEXITCODE
    if ($vcode -eq 0) { Write-Host 'Verification finished.' -ForegroundColor Green }
    else { Write-Host "Verification exited with code $vcode" -ForegroundColor Yellow }
} catch {
    Write-Host "Error running verification: $_" -ForegroundColor Red
}
