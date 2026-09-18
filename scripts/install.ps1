function Install-App {
    param (
        [string]$FilePath,
        [string]$SilentArgs
    )

    Write-Host "  [INSTALL] Starting installation..." -ForegroundColor Cyan

    try {
        $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        
        if ($FilePath -like "*.msi") {
            $processStartInfo.FileName = "msiexec.exe"
            $processStartInfo.Arguments = "/i `"$FilePath`" $SilentArgs"
            Write-Host "  [INSTALL] Running MSI installer with args: /i `"$FilePath`" $SilentArgs" -ForegroundColor DarkCyan
        } else {
            $processStartInfo.FileName = $FilePath
            if ($SilentArgs) {
                $processStartInfo.Arguments = $SilentArgs
                Write-Host "  [INSTALL] Using silent args: $SilentArgs" -ForegroundColor DarkCyan
            } else {
                Write-Host "  [INSTALL] No silent arguments provided. Interactive mode." -ForegroundColor Yellow
            }
        }
        
        $processStartInfo.UseShellExecute = $true

        $process = [System.Diagnostics.Process]::Start($processStartInfo)
        
        if ($process) {
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            if ($exitCode -eq 0 -or $exitCode -eq 3010) { # 3010 is restart required, still a success
                Write-Host "  [INSTALL] Successfully installed." -ForegroundColor Green
                return $true
            } else {
                Write-Host "  [INSTALL] Installer exited with code $exitCode." -ForegroundColor Red
                return $false
            }
        } else {
             Write-Host "  [INSTALL] Process already exited or failed to start." -ForegroundColor Red
             return $false
        }
    }
    catch {
        Write-Host "  [INSTALL] Error during installation: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Export-ModuleMember -Function Install-App
