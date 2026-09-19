# ============================================================
# SULTAN SETUP CENTER - Main Execution Script
# Mode: SUPER FAST  Parallel Download + Sequential Install
# ============================================================

if ((Get-ExecutionPolicy -Scope Process) -ne 'Bypass') {
    Set-ExecutionPolicy Bypass -Scope Process -Force
}

# Require Admin Rights
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Administrator permissions required. Requesting elevation..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/sultan9901/STREAM-SETUP-CENTER/main/install.ps1 | iex`"" -Verb RunAs
    }
    exit
}

# Determine Script Directory (Local vs Remote Execution)
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "apps.json"))) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Join-Path $env:TEMP "STREAM-SETUP-CENTER"
    if (-not (Test-Path $ScriptDir)) {
        New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
    }

    $scriptsDir = Join-Path $ScriptDir "scripts"
    $configDir  = Join-Path $ScriptDir "config"
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $configDir  -Force | Out-Null

    Write-Host "Fetching configuration and modules from GitHub..." -ForegroundColor Cyan
    $baseUrl = "https://raw.githubusercontent.com/sultan9901/STREAM-SETUP-CENTER/main"

    Invoke-RestMethod -Uri "$baseUrl/apps.json"              -OutFile (Join-Path $ScriptDir  "apps.json")
    Invoke-RestMethod -Uri "$baseUrl/config/settings.json"  -OutFile (Join-Path $configDir  "settings.json")
    Invoke-RestMethod -Uri "$baseUrl/scripts/ui.ps1"        -OutFile (Join-Path $scriptsDir "ui.ps1")
    Invoke-RestMethod -Uri "$baseUrl/scripts/download.ps1"  -OutFile (Join-Path $scriptsDir "download.ps1")
    Invoke-RestMethod -Uri "$baseUrl/scripts/verify.ps1"    -OutFile (Join-Path $scriptsDir "verify.ps1")
    Invoke-RestMethod -Uri "$baseUrl/scripts/install.ps1"   -OutFile (Join-Path $scriptsDir "install.ps1")
    Invoke-RestMethod -Uri "$baseUrl/scripts/logger.ps1"    -OutFile (Join-Path $scriptsDir "logger.ps1")
}

# Load Scripts
. (Join-Path $ScriptDir "scripts\ui.ps1")
. (Join-Path $ScriptDir "scripts\download.ps1")
. (Join-Path $ScriptDir "scripts\verify.ps1")
. (Join-Path $ScriptDir "scripts\install.ps1")
. (Join-Path $ScriptDir "scripts\logger.ps1")

# Load Configuration
$ConfigPath = Join-Path $ScriptDir "config\settings.json"
$AppsPath   = Join-Path $ScriptDir "apps.json"

if (-not (Test-Path $ConfigPath) -or -not (Test-Path $AppsPath)) {
    Write-Host "Configuration files missing!" -ForegroundColor Red
    Pause; exit
}

$Config   = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$AppsList = (Get-Content $AppsPath  -Raw | ConvertFrom-Json).apps

# Initialize Temp & Log Directories
$TempDir = Join-Path $env:TEMP "SULTAN_SETUP_DOWNLOADS"
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

$LogDir = Join-Path $ScriptDir "logs"
Init-Logger -LogDir $LogDir

# Internet Check
function Test-Internet {
    try {
        $req = [System.Net.WebRequest]::Create("https://www.google.com")
        $req.Timeout = 5000
        $res = $req.GetResponse()
        $res.Close()
        return $true
    } catch { return $false }
}

Show-Header
Write-UIInfo "Initializing system..."
Write-Log "Setup Started."

if (-not (Test-Internet)) {
    Write-UIError "Internet connection unavailable."
    Write-Log "FAILED: No internet connection."
    Pause; exit
}

Write-UISuccess "System Ready. Starting SUPER FAST installation process."
Write-Log "System checks passed."

# Get enabled apps
$EnabledApps = $AppsList | Where-Object { $_.enabled -eq $true }
$TotalApps   = $EnabledApps.Count

Write-Host ""
Write-Host "  Total apps to install: $TotalApps" -ForegroundColor White
Write-Host ""

# ============================================================
# PHASE 1: SUPER FAST PARALLEL DOWNLOAD
# All files downloaded simultaneously using Runspace Pool
# ============================================================

Show-Header
Write-Host ""
Write-Host "  " -ForegroundColor Cyan
Write-Host "    PHASE 1: PARALLEL DOWNLOAD ENGINE  " -ForegroundColor Cyan
Write-Host "  " -ForegroundColor Cyan
Write-Host ""

Write-Log "Phase 1: Starting parallel download of $TotalApps apps."

$downloadResults = Start-ParallelDownloads -Apps $EnabledApps -TempDir $TempDir -MaxConcurrent 32 -Retries 3

Write-Log "Phase 1: Parallel download complete."

# ============================================================
# PHASE 2: VERIFY + INSTALL (Sequential  no conflicts)
# ============================================================

Show-Header
Write-Host ""
Write-Host "  " -ForegroundColor Green
Write-Host "    PHASE 2: VERIFY & INSTALL          " -ForegroundColor Green
Write-Host "  " -ForegroundColor Green
Write-Host ""

Write-Log "Phase 2: Starting verify + install."

$CurrentAppIndex = 0
$SuccessCount    = 0
$FailedCount     = 0
$SkippedCount    = 0
$FailedApps      = @()

foreach ($app in $EnabledApps) {
    $CurrentAppIndex++
    $InstallerPath = Join-Path $TempDir $app.filename

    Show-Header
    Show-AppStatus -AppName $app.name -Current $CurrentAppIndex -Total $TotalApps
    Write-Log "Processing: $($app.name)"

    try {
        # Check if file exists (should be downloaded in Phase 1)
        if (-not (Test-Path $InstallerPath)) {
            # Try single download as fallback
            Show-Step "DOWNLOAD"
            Write-Host ""
            Write-Host "  [DOWNLOAD] File missing from parallel phase, downloading now..." -ForegroundColor Yellow
            Download-File -Url $app.url -Destination $InstallerPath
        } else {
            Write-Host "  [DOWNLOAD] Already downloaded in Phase 1. " -ForegroundColor DarkGray
        }

        # Verify Hash
        Show-Step "VERIFY  "
        Write-Host ""
        $isHashValid = Test-FileHashMatch -FilePath $InstallerPath -ExpectedHash $app.sha256

        if (-not $isHashValid -and $app.sha256 -ne "PLACEHOLDER") {
            Write-UIError "Integrity check failed. Deleting and re-downloading..."
            Remove-Item $InstallerPath -Force
            # Re-download once
            Download-File -Url $app.url -Destination $InstallerPath
            $isHashValid = Test-FileHashMatch -FilePath $InstallerPath -ExpectedHash $app.sha256
            if (-not $isHashValid) {
                throw "Hash mismatch after re-download"
            }
        }
        if ($app.sha256 -eq "PLACEHOLDER") {
            Write-UIWarning "Skipping hash check (PLACEHOLDER used)."
        }

        # Install
        Show-Step "INSTALL "
        Write-Host ""
        $installSuccess = Install-App -FilePath $InstallerPath -SilentArgs $app.silentArgs

        if ($installSuccess) {
            $SuccessCount++
            Write-Log "Successfully installed: $($app.name)"
            if ($Config.cleanupAfterInstall) {
                Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
            }
        } else {
            throw "Installation process returned error."
        }

    } catch {
        $FailedCount++
        $FailedApps += $app.name
        Write-Log "FAILED: $($app.name) - $($_.Exception.Message)"
        Write-UIError "Failed to install $($app.name): $($_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}

# ============================================================
# FINAL SUMMARY
# ============================================================

Show-Header
Write-Host ""
Write-Host "  " -ForegroundColor Cyan
Write-Host "           INSTALLATION SUMMARY           " -ForegroundColor Cyan
Write-Host "  " -ForegroundColor Cyan
Write-Host ""
Write-Host "   SUCCESS : $SuccessCount" -ForegroundColor Green
Write-Host "   SKIPPED : $SkippedCount" -ForegroundColor DarkGray
Write-Host "   FAILED  : $FailedCount"  -ForegroundColor $(if ($FailedCount -gt 0) { "Red" } else { "Green" })

if ($FailedCount -gt 0) {
    Write-Host ""
    Write-Host "  Failed Applications:" -ForegroundColor Red
    foreach ($f in $FailedApps) {
        Write-Host "    - $f" -ForegroundColor Red
    }
}

Write-Log "Setup Complete. Success: $SuccessCount, Failed: $FailedCount, Skipped: $SkippedCount"
Write-Host ""
Write-Host "  All operations completed. Check logs for details." -ForegroundColor Cyan
Write-Host ""
Pause
