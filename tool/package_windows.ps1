param([string]$Version = '')
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if (!$Version) {
    $Version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches.Groups[1].Value)
}
if ($Version -notmatch '^\d+\.\d+\.\d+(\+[\d.]+)?$') { throw 'Invalid package version' }
$bundle = 'build/windows/x64/runner/Release'
foreach ($file in @('kuraku.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/assets/bin/windows-x64/kuraku.exe')) {
    if (!(Test-Path "$bundle/$file")) { throw "Missing bundle file: $file" }
}
if (!(Get-ChildItem $bundle -Filter '*sqlite3*.dll')) { throw 'Missing SQLite native asset' }
if (!(Get-ChildItem $bundle -Filter '*mpv*.dll')) { throw 'Missing media_kit playback library' }
if (!(Test-Path "$bundle/libffmpegkit.dll")) { throw 'Missing FFmpegKit library' }
# Flutter plugins also need the Visual C++ runtime on a clean Windows machine.
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Visual Studio C++ tools not found' }
$crt = Get-ChildItem "$vs/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
if (!$crt) { throw 'Visual C++ redistributable files not found' }
Copy-Item "$($crt.FullName)/*.dll" $bundle -Force
New-Item -ItemType Directory -Path dist -Force | Out-Null
$archive = "dist/KuraKu-$Version-windows-x64.zip"
Compress-Archive -Path "$bundle/*" -DestinationPath $archive -Force
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $(Split-Path $archive -Leaf)" | Set-Content "$archive.sha256" -Encoding ascii
Write-Output "Packaged $archive"
