# ============================================================
# STREAM SETUP CENTER - Download Module
# Supports: Single download + Super-Fast Parallel Downloads
# ============================================================

# ---- Single File Download (with retry) ----
function Download-File {
    param (
        [string]$Url,
        [string]$Destination,
        [int]$Retries = 3
    )

    $Attempt = 0
    $Success = $false

    while ($Attempt -lt $Retries -and -not $Success) {
        $Attempt++
        try {
            Write-Host "  [DOWNLOAD] Downloading from $Url (Attempt $Attempt)..." -ForegroundColor Cyan

            # Use BITS if available for faster transfer (Windows built-in multi-threaded)
            if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Start-BitsTransfer -Source $Url -Destination $Destination -TransferType Download -ErrorAction Stop
            } else {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "Mozilla/5.0 StreamSetupCenter/1.0")
                $wc.DownloadFile($Url, $Destination)
            }

            $Success = $true
            Write-Host "  [DOWNLOAD] Complete." -ForegroundColor Green
        }
        catch {
            Write-Host "  [DOWNLOAD] Failed: $($_.Exception.Message)" -ForegroundColor Red
            if (Test-Path $Destination) { Remove-Item $Destination -Force -ErrorAction SilentlyContinue }
            if ($Attempt -lt $Retries) {
                Write-Host "  [DOWNLOAD] Retrying in 3 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 3
            }
        }
    }

    if (-not $Success) {
        throw "Failed to download $Url after $Retries attempts."
    }
}

# ---- SUPER FAST: Parallel Download All Apps Using Runspaces ----
function Start-ParallelDownloads {
    param (
        [array]$Apps,
        [string]$TempDir,
        [int]$MaxConcurrent = 8,
        [int]$Retries = 3
    )

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   SUPER FAST PARALLEL DOWNLOAD ENGINE   ║" -ForegroundColor Cyan
    Write-Host "  ║   Downloading all $($Apps.Count) files simultaneously  ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    $startTime = Get-Date

    # Filter out already-downloaded files
    $toDownload = @()
    $alreadyCached = @()
    foreach ($app in $Apps) {
        $dest = Join-Path $TempDir $app.filename
        if (Test-Path $dest) {
            $alreadyCached += $app
        } else {
            $toDownload += $app
        }
    }

    if ($alreadyCached.Count -gt 0) {
        Write-Host "  [CACHE] $($alreadyCached.Count) file(s) already downloaded. Skipping re-download." -ForegroundColor DarkGray
    }

    if ($toDownload.Count -eq 0) {
        Write-Host "  [CACHE] All files already cached! Skipping download phase." -ForegroundColor Green
        return @{}
    }

    Write-Host "  [PARALLEL] Starting $($toDownload.Count) downloads (max $MaxConcurrent concurrent)..." -ForegroundColor Yellow
    Write-Host ""

    # Build runspace pool
    $RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxConcurrent)
    $RunspacePool.Open()

    # Script block executed in each runspace
    $DownloadScript = {
        param($Url, $Destination, $Filename, $Retries)

        $result = @{
            Filename = $Filename
            Success  = $false
            Error    = ""
            Bytes    = 0
        }

        for ($i = 1; $i -le $Retries; $i++) {
            try {
                # Try BITS first, fall back to WebClient
                $useBits = $null -ne (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue)
                if ($useBits) {
                    Start-BitsTransfer -Source $Url -Destination $Destination -TransferType Download -ErrorAction Stop
                } else {
                    $wc = New-Object System.Net.WebClient
                    $wc.Headers.Add("User-Agent", "Mozilla/5.0 StreamSetupCenter/1.0")
                    $wc.DownloadFile($Url, $Destination)
                }
                $result.Success = $true
                $result.Bytes   = (Get-Item $Destination -ErrorAction SilentlyContinue).Length
                break
            } catch {
                $result.Error = $_.Exception.Message
                if (Test-Path $Destination) { Remove-Item $Destination -Force -ErrorAction SilentlyContinue }
                if ($i -lt $Retries) { Start-Sleep -Seconds 3 }
            }
        }
        return $result
    }

    # Launch all runspace jobs
    $Jobs = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($app in $toDownload) {
        $dest = Join-Path $TempDir $app.filename
        $ps   = [System.Management.Automation.PowerShell]::Create()
        $ps.RunspacePool = $RunspacePool
        [void]$ps.AddScript($DownloadScript)
        [void]$ps.AddArgument($app.url)
        [void]$ps.AddArgument($dest)
        [void]$ps.AddArgument($app.filename)
        [void]$ps.AddArgument($Retries)
        $handle = $ps.BeginInvoke()
        $Jobs.Add(@{ PS = $ps; Handle = $handle; Name = $app.name; Filename = $app.filename })
    }

    # Live progress monitor
    $completed = 0
    $total     = $Jobs.Count
    $results   = @{}

    Write-Host "  Progress:" -ForegroundColor White

    while ($completed -lt $total) {
        Start-Sleep -Milliseconds 500
        $done = $Jobs | Where-Object { $_.Handle.IsCompleted }
        foreach ($job in $done) {
            if ($results.ContainsKey($job.Filename)) { continue }
            $output = $job.PS.EndInvoke($job.Handle)
            $job.PS.Dispose()
            $res = $output[0]
            $results[$job.Filename] = $res
            $completed++
            $pct = [math]::Round(($completed / $total) * 100)
            $bar = "#" * [math]::Round($pct / 5)
            $space = " " * (20 - $bar.Length)
            if ($res.Success) {
                $sizeKB = [math]::Round($res.Bytes / 1KB)
                Write-Host "  [$bar$space] $pct% | [OK] $($job.Name) ($sizeKB KB)" -ForegroundColor Green
            } else {
                Write-Host "  [$bar$space] $pct% | [FAIL] $($job.Name): $($res.Error)" -ForegroundColor Red
            }
        }
    }

    $RunspacePool.Close()
    $RunspacePool.Dispose()

    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    $successCount = ($results.Values | Where-Object { $_.Success }).Count
    $failCount    = $total - $successCount

    Write-Host ""
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  [DONE] $successCount/$total downloaded in ${elapsed}s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
    if ($failCount -gt 0) {
        Write-Host "  [WARN] $failCount file(s) failed to download." -ForegroundColor Red
    }
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return $results
}

# ---- Disk Space Check ----
function Test-DiskSpace {
    param (
        [string]$Path,
        [long]$RequiredBytes
    )

    $drive = Split-Path $Path -Qualifier
    if (-not $drive) {
        $drive = (Get-Item $Path).PSDrive.Name + ":"
    }

    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$drive'"
    if ($disk.FreeSpace -lt $RequiredBytes) {
        return $false
    }
    return $true
}
