$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engineDirectory = Join-Path $projectRoot '.tools/godot'
New-Item -ItemType Directory -Force $engineDirectory | Out-Null
$archivePath = Join-Path $engineDirectory 'godot.zip'
$releaseUrl = 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip'
if (-not (Test-Path -LiteralPath $archivePath)) {
    Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
}
$expectedHash = '731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953'
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLower() -ne $expectedHash) {
    throw 'Godot archive checksum does not match the official release digest.'
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $engineDirectory -Force
& (Join-Path $engineDirectory 'Godot_v4.7.2-stable_win64_console.exe') --version
