$ErrorActionPreference = 'Stop'
$toolsDir = $PSScriptRoot
$nativeDir = (Resolve-Path "$toolsDir/../..").Path
$rdpBuild = "$nativeDir/build/rdp/windows"
# Vcpkg uses the same target architecture as Flutter (x64 by default).
$triplet = if ($env:EASYNODE_RDP_TRIPLET) { $env:EASYNODE_RDP_TRIPLET } else { 'x64-windows' }
if (-not $env:VCPKG_ROOT) { throw 'Set VCPKG_ROOT to a bootstrapped vcpkg checkout. Required tools: VS C++, CMake, Python 3.9+.' }
function Invoke-Checked($exe, [string[]]$arguments) {
  & $exe @arguments
  if ($LASTEXITCODE -ne 0) { throw "$exe failed ($LASTEXITCODE)" }
}
Invoke-Checked "$env:VCPKG_ROOT/vcpkg.exe" @('install', "sdl3:$triplet", "sdl3-ttf:$triplet", "openssl:$triplet", "zlib:$triplet", "cjson:$triplet")
$source = & python "$toolsDir/prepare.py" "$nativeDir/build/rdp/source"
if ($LASTEXITCODE -ne 0) { throw 'FreeRDP source preparation failed' }
$arch = if ($triplet.StartsWith('arm64')) { 'ARM64' } else { 'x64' }
Invoke-Checked 'cmake' @('-S', $source, '-B', "$rdpBuild/cmake", '-A', $arch, '-C', "$toolsDir/engine-options.cmake",
  "-DCMAKE_TOOLCHAIN_FILE=$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake", "-DVCPKG_TARGET_TRIPLET=$triplet", "-DCMAKE_INSTALL_PREFIX=$rdpBuild/install")
Invoke-Checked 'cmake' @('--build', "$rdpBuild/cmake", '--config', 'Release', '--target', 'sdl3-freerdp', '--parallel')
Invoke-Checked 'cmake' @('--install', "$rdpBuild/cmake", '--config', 'Release', '--component', 'libraries')
Invoke-Checked 'cmake' @('--install', "$rdpBuild/cmake", '--config', 'Release', '--component', 'client')
if (Test-Path "$rdpBuild/bundle") { Remove-Item "$rdpBuild/bundle" -Recurse -Force }
New-Item "$rdpBuild/bundle/licenses" -ItemType Directory -Force | Out-Null
Copy-Item "$rdpBuild/install/bin/easynode-rdp.exe" "$rdpBuild/bundle/"
Copy-Item "$rdpBuild/install/bin/*.dll" "$rdpBuild/bundle/" -ErrorAction SilentlyContinue
# Include every installed runtime DLL: all codec/font/crypto dependencies must
# travel with the helper, never be resolved from a user-installed RDP client.
Copy-Item "$env:VCPKG_ROOT/installed/$triplet/bin/*.dll" "$rdpBuild/bundle/"
Get-ChildItem "$env:VCPKG_ROOT/installed/$triplet/share" -Directory | ForEach-Object {
  if (Test-Path "$($_.FullName)/copyright") { Copy-Item "$($_.FullName)/copyright" "$rdpBuild/bundle/licenses/$($_.Name).txt" }
}
Copy-Item "$source/resources/font/OFL.txt" "$rdpBuild/bundle/licenses/OpenSans-OFL.txt"
Copy-Item "$source/client/SDL/SDL3/dialogs/font/OFL.txt" "$rdpBuild/bundle/licenses/SDL-dialog-font-OFL.txt"
Copy-Item "$source/LICENSE" "$rdpBuild/bundle/licenses/FreeRDP-LICENSE"
Set-Content "$rdpBuild/bundle/engine-version.txt" 'FreeRDP 3.32.2 + EasyNode SDL3 IPC'
Write-Host 'RDP engine prepared. Rebuild EasyNode to embed it.'
