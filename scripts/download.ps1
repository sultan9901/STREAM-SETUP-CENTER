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
            
            # Using System.Net.WebClient for better performance than Invoke-WebRequest on older PS versions
            $webClient = New-Object System.Net.WebClient
            
            # If we want progress, we could hook into DownloadProgressChanged, but that requires event subscriptions.
            # To keep it beginner-friendly and stable across PS versions, we'll use a simpler approach.
            # We will use Invoke-WebRequest for progress if PS version is high, or WebClient for speed.
            
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop
            } else {
                # In PS 5.1, Invoke-WebRequest is slow. Using WebClient.
                $webClient.DownloadFile($Url, $Destination)
            }
            
            $Success = $true
            Write-Host "  [DOWNLOAD] Complete." -ForegroundColor Green
        }
        catch {
            Write-Host "  [DOWNLOAD] Failed: $($_.Exception.Message)" -ForegroundColor Red
            if ($Attempt -lt $Retries) {
                Write-Host "  [DOWNLOAD] Retrying in 5 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            }
        }
    }

    if (-not $Success) {
        throw "Failed to download $Url after $Retries attempts."
    }
}

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

Export-ModuleMember -Function Download-File, Test-DiskSpace
