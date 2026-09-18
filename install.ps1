# STREAM SETUP CENTER - Main Execution Script
# Ensure PowerShell runs with proper Execution Policy
if ((Get-ExecutionPolicy -Scope Process) -ne 'Bypass') {
    Set-ExecutionPolicy Bypass -Scope Process -Force
}

# Require Admin Rights
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Administrator permissions required. Requesting elevation..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Import Modules
Import-Module (Join-Path $ScriptDir "scripts\ui.ps1") -Force
Import-Module (Join-Path $ScriptDir "scripts\download.ps1") -Force
Import-Module (Join-Path $ScriptDir "scripts\verify.ps1") -Force
Import-Module (Join-Path $ScriptDir "scripts\install.ps1") -Force
Import-Module (Join-Path $ScriptDir "scripts\logger.ps1") -Force

# Load Configuration
$ConfigPath = Join-Path $ScriptDir "config\settings.json"
$AppsPath = Join-Path $ScriptDir "apps.json"

if (-not (Test-Path $ConfigPath) -or -not (Test-Path $AppsPath)) {
    Write-Host "Configuration files missing! Please ensure config\settings.json and apps.json exist." -ForegroundColor Red
    Pause
    exit
}

$Config = Get-Content $ConfigPath | ConvertFrom-Json
$AppsList = (Get-Content $AppsPath | ConvertFrom-Json).apps

# Initialize Environment
$TempDir = [System.Environment]::ExpandEnvironmentVariables($Config.tempDownloadPath)
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

$LogDir = Join-Path $ScriptDir "logs"
Init-Logger -LogDir $LogDir

# Check Internet Connection
function Test-Internet {
    try {
        $req = [System.Net.WebRequest]::Create("https://www.google.com")
        $req.Timeout = 5000
        $res = $req.GetResponse()
        $res.Close()
        return $true
    } catch {
        return $false
    }
}

Show-Header
Write-UIInfo "Initializing system..."
Write-Log "Setup Started."

if (-not (Test-Internet)) {
    Write-UIError "Internet connection unavailable."
    Write-Log "FAILED: No internet connection."
    Pause
    exit
}

Write-UISuccess "System Ready. Starting installation process."
Write-Log "System checks passed."
Start-Sleep -Seconds 2

$TotalApps = ($AppsList | Where-Object { $_.enabled -eq $true }).Count
$CurrentAppIndex = 0
$SuccessCount = 0
$FailedCount = 0
$SkippedCount = 0
$FailedApps = @()

foreach ($app in $AppsList) {
    if (-not $app.enabled) {
        Write-Log "Skipped disabled app: $($app.name)"
        continue
    }

    $CurrentAppIndex++
    Show-Header
    Show-AppStatus -AppName $app.name -Current $CurrentAppIndex -Total $TotalApps
    Write-Log "Processing: $($app.name)"

    # Detect if already installed (Simple logic based on registry or custom script could be added here)
    # For now, we will proceed with download/install as requested, 
    # a robust detection mechanism requires specific registry keys per app.

    $InstallerPath = Join-Path $TempDir $app.filename

    # Step 1: Download
    Show-Step "DOWNLOAD"
    try {
        if (Test-Path $InstallerPath) {
            Write-Host "`n  [DOWNLOAD] File already exists, verifying hash..." -ForegroundColor DarkGray
        } else {
            Write-Host ""
            Download-File -Url $app.url -Destination $InstallerPath
        }
        
        # Step 2: Verify
        Show-Step "VERIFY  "
        Write-Host ""
        $isHashValid = Test-FileHashMatch -FilePath $InstallerPath -ExpectedHash $app.sha256

        if (-not $isHashValid -and $app.sha256 -ne "PLACEHOLDER") {
            Write-UIError "Integrity check failed. Deleting file."
            Remove-Item $InstallerPath -Force
            throw "Hash mismatch"
        }
        if ($app.sha256 -eq "PLACEHOLDER") {
            Write-UIWarning "Skipping hash check (PLACEHOLDER used)."
        }

        # Step 3: Install
        Show-Step "INSTALL "
        Write-Host ""
        $installSuccess = Install-App -FilePath $InstallerPath -SilentArgs $app.silentArgs

        if ($installSuccess) {
            $SuccessCount++
            Write-Log "Successfully installed: $($app.name)"
            if ($Config.cleanupAfterInstall) {
                Remove-Item $InstallerPath -Force
            }
        } else {
            throw "Installation process returned error."
        }

    } catch {
        $FailedCount++
        $FailedApps += $app.name
        Write-Log "FAILED: $($app.name) - $($_.Exception.Message)"
        Write-UIError "Failed to install $($app.name)."
        Start-Sleep -Seconds 3
    }
}

Show-Header
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "          INSTALLATION SUMMARY" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "SUCCESS: $SuccessCount" -ForegroundColor Green
Write-Host "SKIPPED: $SkippedCount" -ForegroundColor DarkGray
Write-Host "FAILED:  $FailedCount" -ForegroundColor Red

if ($FailedCount -gt 0) {
    Write-Host "`nFailed Applications:" -ForegroundColor Red
    foreach ($f in $FailedApps) {
        Write-Host "- $f" -ForegroundColor Red
    }
}

Write-Log "Setup Complete. Success: $SuccessCount, Failed: $FailedCount, Skipped: $SkippedCount"
Write-Host "`nAll operations completed. Check logs for details." -ForegroundColor Cyan
Pause
