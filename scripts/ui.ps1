function Show-Header {
    Clear-Host
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "Gray"
    Clear-Host

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       STREAM SETUP CENTER" -ForegroundColor Cyan -NoNewline
    Write-Host " "
    Write-Host "       WINDOWS SOFTWARE INSTALLER" -ForegroundColor DarkCyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-UIInfo {
    param (
        [string]$Message
    )
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-UISuccess {
    param (
        [string]$Message
    )
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-UIWarning {
    param (
        [string]$Message
    )
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-UIError {
    param (
        [string]$Message
    )
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-UISkip {
    param (
        [string]$Message
    )
    Write-Host "[SKIPPED] $Message" -ForegroundColor DarkGray
}

function Show-AppStatus {
    param (
        [string]$AppName,
        [int]$Current,
        [int]$Total
    )
    Write-Host "`n[$Current/$Total] $AppName" -ForegroundColor White
}

function Show-Step {
    param (
        [string]$StepName
    )
    Write-Host "  [$StepName] " -ForegroundColor DarkCyan -NoNewline
}

function Show-StepDone {
    Write-Host "Done" -ForegroundColor Green
}

function Show-StepFail {
    Write-Host "Failed" -ForegroundColor Red
}
