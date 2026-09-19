function Test-FileHashMatch {
    param (
        [string]$FilePath,
        [string]$ExpectedHash
    )

    if (-not (Test-Path $FilePath)) {
        return $false
    }

    Write-Host "  [VERIFY] Calculating SHA-256 for $(Split-Path $FilePath -Leaf)..." -ForegroundColor Cyan
    
    try {
        $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        
        if ($actualHash -eq $ExpectedHash) {
            Write-Host "  [VERIFY] Hash matched!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  [VERIFY] HASH MISMATCH!" -ForegroundColor Red
            Write-Host "    Expected: $ExpectedHash" -ForegroundColor Red
            Write-Host "    Actual:   $actualHash" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "  [VERIFY] Error calculating hash: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}
