function Init-Logger {
    param (
        [string]$LogDir
    )
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $Global:LogFilePath = Join-Path $LogDir "$timestamp.log"
    
    Write-Log "========================================"
    Write-Log "STREAM SETUP CENTER LOG - $timestamp"
    Write-Log "========================================"
}

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    if (-not $Global:LogFilePath) { return }
    
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$time] [$Level] $Message"
    
    Add-Content -Path $Global:LogFilePath -Value $logLine
}
