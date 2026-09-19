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

            # Known success/skip exit codes:
            # 0     = Success
            # 3010  = Success, restart required
            # 1638  = Another version already installed (already present = OK)
            # 1641  = Success, system restart initiated
            # -9    = DirectX already up-to-date on this Windows version

            switch ($exitCode) {
                0 {
                    Write-Host "  [INSTALL] Successfully installed." -ForegroundColor Green
                    return $true
                }
                3010 {
                    Write-Host "  [INSTALL] Installed successfully. A restart is recommended." -ForegroundColor Yellow
                    return $true
                }
                1638 {
                    Write-Host "  [INSTALL] Already installed (same or newer version present). Skipping." -ForegroundColor Yellow
                    return $true
                }
                1641 {
                    Write-Host "  [INSTALL] Installed successfully. System restart initiated." -ForegroundColor Yellow
                    return $true
                }
                -9 {
                    Write-Host "  [INSTALL] Component already present or up-to-date on this system." -ForegroundColor Yellow
                    return $true
                }
                default {
                    Write-Host "  [INSTALL] Installer exited with code $exitCode." -ForegroundColor Red
                    return $false
                }
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
