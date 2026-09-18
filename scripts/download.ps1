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
            
            $webClient = New-Object System.Net.WebClient
            
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop
            } else {
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
