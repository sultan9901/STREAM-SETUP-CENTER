param(
    [Parameter(Mandatory=$true)]
    [string]$InstallerFolder
)

if (-not (Test-Path $InstallerFolder)) {
    Write-Host "Folder not found: $InstallerFolder" -ForegroundColor Red
    exit
}

Write-Host "Scanning installers in $InstallerFolder..." -ForegroundColor Cyan

$files = Get-ChildItem -Path $InstallerFolder -Filter "*.exe"

$apps = @()

foreach ($file in $files) {
    Write-Host "Processing $($file.Name)..."
    
    $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
    
    $app = @{
        name = $file.BaseName
        version = "unknown"
        filename = $file.Name
        url = "https://github.com/USERNAME/STREAM-SETUP-CENTER/releases/download/v1.0/$($file.Name)"
        sha256 = $hash
        silentArgs = ""
        enabled = $true
        category = "Uncategorized"
    }
    
    $apps += $app
}

$output = @{ apps = $apps }
$json = $output | ConvertTo-Json -Depth 3
$jsonPath = Join-Path $PWD "generated_apps.json"

Set-Content -Path $jsonPath -Value $json -Encoding UTF8

Write-Host "Done! Configuration saved to $jsonPath" -ForegroundColor Green
Write-Host "You can now merge this with your main apps.json" -ForegroundColor Yellow
