$ErrorActionPreference = 'Stop'
$version = '2.10.0'
$workspacePath = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $workspacePath '.tools\spacetime'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$release = Invoke-RestMethod "https://api.github.com/repos/clockworklabs/SpacetimeDB/releases/tags/v$version"
$asset = $release.assets | Where-Object name -eq 'spacetime-x86_64-pc-windows-msvc.zip'
if (-not $asset) { throw 'Official Windows release not found' }
$archivePath = Join-Path $workspacePath ".tools\spacetime-$version.zip"
Invoke-WebRequest $asset.browser_download_url -OutFile $archivePath
if ($asset.digest -and $asset.digest.StartsWith('sha256:')) {
  $actual = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLower()
  if ($actual -ne $asset.digest.Substring(7)) { throw 'Release checksum mismatch' }
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $destination -Force
Push-Location $workspacePath
try { npm ci --prefix spacetimedb --ignore-scripts; if ($LASTEXITCODE -ne 0) { throw 'Module dependencies failed' } }
finally { Pop-Location }
Write-Output "SpacetimeDB $version installed locally in $destination"
