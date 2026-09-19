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
    $Success  = $false

    while ($Attempt -lt $Retries -and -not $Success) {
        $Attempt++
        try {
            $msg = "  [DOWNLOAD] Downloading (Attempt " + $Attempt + ")..."
            Write-Host $msg -ForegroundColor Cyan

            # Use BITS if available (Windows built-in, multi-threaded)
            $bitsAvail = $null -ne (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue)
            if ($bitsAvail) {
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
            $errMsg = $_.Exception.Message
            Write-Host "  [DOWNLOAD] Failed: $errMsg" -ForegroundColor Red
            if (Test-Path $Destination) {
                Remove-Item $Destination -Force -ErrorAction SilentlyContinue
            }
            if ($Attempt -lt $Retries) {
                Write-Host "  [DOWNLOAD] Retrying in 3 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 3
            }
        }
    }

    if (-not $Success) {
        $errFinal = "Failed to download after " + $Retries + " attempts: " + $Url
        throw $errFinal
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
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |  SUPER FAST PARALLEL DOWNLOAD ENGINE     |" -ForegroundColor Cyan
    $countLine = "  |  Downloading " + $Apps.Count + " files simultaneously      |"
    Write-Host $countLine -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    $startTime = Get-Date

    # Split into cached vs. needs downloading
    $toDownload    = @()
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
        $cacheMsg = "  [CACHE] " + $alreadyCached.Count + " file(s) already cached - skipping re-download."
        Write-Host $cacheMsg -ForegroundColor DarkGray
    }

    if ($toDownload.Count -eq 0) {
        Write-Host "  [CACHE] All files already cached! Skipping download phase." -ForegroundColor Green
        return @{}
    }

    $startMsg = "  [PARALLEL] Starting " + $toDownload.Count + " downloads (max " + $MaxConcurrent + " concurrent)..."
    Write-Host $startMsg -ForegroundColor Yellow
    Write-Host ""

    # Build runspace pool
    $RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxConcurrent)
    $RunspacePool.Open()

    # Script block run in each runspace
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
                $useBits = $null -ne (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue)
                if ($useBits) {
                    Start-BitsTransfer -Source $Url -Destination $Destination -TransferType Download -ErrorAction Stop
                } else {
                    $wc = New-Object System.Net.WebClient
                    $wc.Headers.Add("User-Agent", "Mozilla/5.0 StreamSetupCenter/1.0")
                    $wc.DownloadFile($Url, $Destination)
                }
                $result.Success = $true
                $fileItem = Get-Item $Destination -ErrorAction SilentlyContinue
                if ($fileItem) { $result.Bytes = $fileItem.Length }
                break
            } catch {
                $result.Error = $_.Exception.Message
                if (Test-Path $Destination) {
                    Remove-Item $Destination -Force -ErrorAction SilentlyContinue
                }
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
        Start-Sleep -Milliseconds 600
        $done = $Jobs | Where-Object { $_.Handle.IsCompleted -eq $true }
        foreach ($job in $done) {
            if ($results.ContainsKey($job.Filename)) { continue }
            $output  = $job.PS.EndInvoke($job.Handle)
            $job.PS.Dispose()
            $res     = $output[0]
            $results[$job.Filename] = $res
            $completed++
            $pct     = [math]::Round(($completed / $total) * 100)
            $barLen  = [math]::Round($pct / 5)
            $bar     = ""
            for ($b = 0; $b -lt $barLen; $b++) { $bar += "#" }
            $spaceLen = 20 - $barLen
            $spaces   = ""
            for ($s = 0; $s -lt $spaceLen; $s++) { $spaces += " " }
            $appName = $job.Name
            if ($res.Success) {
                $sizeKB  = [math]::Round($res.Bytes / 1024)
                $sizeTxt = $sizeKB.ToString() + " KB"
                $line    = "  [" + $bar + $spaces + "] " + $pct + "% | OK   " + $appName + " (" + $sizeTxt + ")"
                Write-Host $line -ForegroundColor Green
            } else {
                $errMsg = $res.Error
                $line   = "  [" + $bar + $spaces + "] " + $pct + "% | FAIL " + $appName + " - " + $errMsg
                Write-Host $line -ForegroundColor Red
            }
        }
    }

    $RunspacePool.Close()
    $RunspacePool.Dispose()

    $elapsed      = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    $successCount = ($results.Values | Where-Object { $_.Success -eq $true }).Count
    $failCount    = $total - $successCount

    Write-Host ""
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    $doneMsg = "  | DONE: " + $successCount + "/" + $total + " downloaded in " + $elapsed + "s"
    Write-Host $doneMsg -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
    if ($failCount -gt 0) {
        $failMsg = "  | WARN: " + $failCount + " file(s) failed to download"
        Write-Host $failMsg -ForegroundColor Red
    }
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
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

    $filter = "DeviceID='" + $drive + "'"
    $disk   = Get-WmiObject Win32_LogicalDisk -Filter $filter
    if ($disk.FreeSpace -lt $RequiredBytes) {
        return $false
    }
    return $true
}
