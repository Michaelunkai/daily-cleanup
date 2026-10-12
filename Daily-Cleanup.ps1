<#
=====================================================================
  Daily-Cleanup.ps1   -   Safe daily C: drive space cleaner
  Machine-tuned for: Admin's PC (Windows 11, PowerShell 5.1+)
=====================================================================
  PHILOSOPHY: delete everything that re-downloads or regenerates
  automatically. Locked/in-use files are skipped automatically
  (Windows refuses to delete a file a running process holds open,
  so nothing running can be broken). Nothing an app needs to
  start, log in, or keep your data is ever touched.

  WHAT IT NEVER TOUCHES (protected on purpose)
    C:\Windows\Installer            (needed for uninstall/repair)
    C:\ProgramData\Package Cache    (same)
    C:\Windows\WinSxS               (only DISM touches it, -Deep)
    C:\Windows\System32\DriverStore (installed drivers)
    C:\wsl2                         (your WSL Linux data)
    C:\Program Files\WindowsApps    (Store apps)
    All browser profiles, bookmarks, passwords, cookies, history,
      extensions, Service Worker data (logins for web apps)
      - ONLY regenerable Cache / shader-cache / model-cache folders
    Plex metadata/database, Everything.db, .zcode db.sqlite
    ProgramData\Microsoft\Search    (search index)
    Restore points (NOT deleted unless you pass -Shadows)
    Any installed app, SDK, or game

  USAGE
    Daily (normal):
      powershell -ExecutionPolicy Bypass -File F:\study\Windows\Applications\Desktop\Utilities\System\Cleanup\Maintenance\daily-cleanup\Daily-Cleanup.ps1
    Weekly deep clean (adds DISM WinSxS cleanup + Windows Update
    cache with service stop):
      ... -Deep
    Also delete restore points (you have Macrium Reflect):
      ... -Shadows

  NOTE: if it frees very little, the disk is already clean - it
  only finds what re-accumulated since the last run.

  TIP - run it automatically every day at 09:00 (one-time, admin):
    schtasks /Create /TN "Daily C Cleanup" /SC DAILY /ST 09:00 /RL HIGHEST /TR "powershell -ExecutionPolicy Bypass -NoProfile -File F:\study\Windows\Applications\Desktop\Utilities\System\Cleanup\Maintenance\daily-cleanup\Daily-Cleanup.ps1"
=====================================================================
#>
[CmdletBinding()]
param(
    [switch]$Deep,
    [switch]$Shadows,
    [switch]$PauseAtEnd
)

# ---------- self-elevate ----------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args2 = @('-ExecutionPolicy','Bypass','-NoProfile','-File', $PSCommandPath, '-PauseAtEnd')
    if ($Deep)    { $args2 += '-Deep' }
    if ($Shadows) { $args2 += '-Shadows' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args2
    exit
}

$ErrorActionPreference = 'SilentlyContinue'
$GB = 1073741824
$sw = [Diagnostics.Stopwatch]::StartNew()
$logDir  = Join-Path $PSScriptRoot 'logs'
$logFile = Join-Path $logDir ("cleanup-{0:yyyy-MM-dd_HHmmss}.log" -f (Get-Date))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$free0 = (Get-PSDrive C).Free
$results = New-Object System.Collections.Generic.List[string]

function Get-PathSize($p) {
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    $s = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -EA SilentlyContinue |
          Measure-Object -Property Length -Sum).Sum
    if ($null -eq $s) { 0 } else { $s }
}

# delete everything INSIDE a folder (folder itself kept; locked files skip silently)
function Clear-Inside($label, $path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $b = Get-PathSize $path
    Get-ChildItem -LiteralPath $path -Force -EA SilentlyContinue |
        Remove-Item -Recurse -Force -EA SilentlyContinue
    $f = $b - (Get-PathSize $path)
    if ($f -gt 1MB) { $results.Add(("  {0,8:N0} MB  {1}" -f ($f/1MB), $label)) }
}

# delete only files older than N days (used for logs and C:\Temp)
function Clear-Older($label, $path, $days) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $cut = (Get-Date).AddDays(-$days)
    $b = 0
    Get-ChildItem -LiteralPath $path -Recurse -Force -File -EA SilentlyContinue |
      Where-Object { $_.LastWriteTime -lt $cut } | ForEach-Object {
        $b += $_.Length
        Remove-Item -LiteralPath $_.FullName -Force -EA SilentlyContinue
      }
    Get-ChildItem -LiteralPath $path -Recurse -Force -Directory -EA SilentlyContinue |
      Sort-Object FullName -Descending | Where-Object {
        -not (Get-ChildItem -LiteralPath $_.FullName -Force -EA SilentlyContinue | Select-Object -First 1)
      } | Remove-Item -Force -EA SilentlyContinue
    if ($b -gt 1MB) { $results.Add(("  {0,8:N0} MB  {1} (older than {2}d)" -f ($b/1MB), $label, $days)) }
}

# delete the folder itself if it exists
function Remove-Folder($label, $path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $b = Get-PathSize $path
    Remove-Item -LiteralPath $path -Recurse -Force -EA SilentlyContinue
    if (-not (Test-Path -LiteralPath $path) -and $b -gt 1MB) {
        $results.Add(("  {0,8:N0} MB  {1}" -f ($b/1MB), $label))
    }
}

function Is-Running($pattern) {
    [bool](Get-Process | Where-Object { $_.Name -match $pattern } | Select-Object -First 1)
}

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host (" Daily C: cleanup  -  started {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
$mode = 'standard'
if ($Deep) { $mode = "$mode DEEP" }
if ($Shadows) { $mode = "$mode SHADOWS" }
Write-Host (" Mode: {0}" -f $mode) -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan

$codexRunning = Is-Running 'codex'

#---------------- 1. TEMP (locked files skip automatically) ----------------
Write-Host ""
Write-Host "[1/9] Temp files" -ForegroundColor Yellow
Clear-Inside 'User temp'         $env:TEMP
Clear-Inside 'Windows temp'      'C:\Windows\Temp'
Clear-Older  'C:\Temp (user-created)' 'C:\Temp' 3
Clear-Inside 'Squirrel temp'     "$env:LOCALAPPDATA\SquirrelTemp"
Clear-Inside 'WinGet temp'       "$env:LOCALAPPDATA\Temp\WinGet"
Clear-Inside 'Mozilla temp files' "$env:LOCALAPPDATA\Temp\mozilla-temp-files"

#---------------- 2. GPU / shader caches (regenerate automatically) ----------------
Write-Host ""
Write-Host "[2/9] GPU and DirectX shader caches" -ForegroundColor Yellow
Clear-Inside 'NVIDIA DXCache'              "$env:LOCALAPPDATA\NVIDIA\DXCache"
Clear-Inside 'NVIDIA GLCache'              "$env:LOCALAPPDATA\NVIDIA\GLCache"
Clear-Inside 'NVIDIA DXCache (LocalLow)'   "$env:USERPROFILE\AppData\LocalLow\NVIDIA\DXCache"
Clear-Inside 'NVIDIA CUDA ComputeCache'    "$env:APPDATA\NVIDIA\ComputeCache"
Clear-Inside 'NVIDIA Corporation NV_Cache' "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache"
Clear-Inside 'NVIDIA App CEF cache'        "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\CefCache"
Clear-Inside 'DirectX D3DSCache'           "$env:LOCALAPPDATA\D3DSCache"
Clear-Inside 'AMD shader cache (dx)'       "$env:LOCALAPPDATA\AMD\DxCache"
Clear-Inside 'AMD shader cache (vk)'       "$env:LOCALAPPDATA\AMD\VkCache"
Clear-Inside 'AMD shader cache (dxc)'      "$env:LOCALAPPDATA\AMD\DxcCache"
Clear-Inside 'AMD shader cache (LocalLow)' "$env:USERPROFILE\AppData\LocalLow\AMD\DxCache"

#---------------- 3. Updater / installer leftovers ----------------
Write-Host ""
Write-Host "[3/9] Updater and installer leftovers" -ForegroundColor Yellow
Clear-Inside 'Ollama setup cache'          "$env:LOCALAPPDATA\Ollama\updates_v2"
Remove-Folder 'LM Studio updater cache'    "$env:LOCALAPPDATA\lm-studio-updater"
Remove-Folder 'Vortex updater cache'       "$env:LOCALAPPDATA\vortex-updater"
Remove-Folder 'CurseForge updater cache'   "$env:LOCALAPPDATA\curseforge-updater"
Remove-Folder 'Paseo updater cache'        "$env:LOCALAPPDATA\@getpaseodesktop-updater"
Remove-Folder 'GameSir updater cache'      "$env:LOCALAPPDATA\gamesir_connect-updater"
Remove-Folder 'Lucid updater cache'        "$env:LOCALAPPDATA\lucidagentide-desktop-updater"
Clear-Inside 'NVIDIA App driver downloads' 'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts'
Clear-Inside 'NVIDIA Downloader cache'     'C:\ProgramData\NVIDIA Corporation\Downloader'
Clear-Inside 'Logitech download cache'     'C:\ProgramData\LogiOptionsPlus\cache'
Clear-Inside 'Edge update installers'      'C:\Program Files (x86)\Microsoft\EdgeUpdate\Download'
Clear-Inside 'Chrome updater cache'        'C:\Program Files (x86)\Google\GoogleUpdater\crx_cache'
Clear-Inside 'WPT redist installers'       'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\Redistributables'
Clear-Inside 'WPR symbol cache'            'C:\ProgramData\WindowsPerformanceRecorder\NGenPdbs_Cache'
Get-ChildItem "$env:USERPROFILE\.zcode\android-build" -Filter *.zip -File -EA SilentlyContinue |
    ForEach-Object { $n=$_.Length; Remove-Item -LiteralPath $_.FullName -Force -EA SilentlyContinue;
        if (-not (Test-Path -LiteralPath $_.FullName) -and $n -gt 1MB) {
            $results.Add(("  {0,8:N0} MB  android-build zip {1}" -f ($n/1MB), $_.Name)) } }

#---------------- 4. Browser caches ONLY (profiles/logins/bookmarks NEVER touched) ----------------
# locked files (browser running) skip automatically; cache rebuilds as you browse
Write-Host ""
Write-Host "[4/9] Browser caches" -ForegroundColor Yellow
$browserCacheSubdirs = @('Cache','Code Cache','GPUCache','GrShaderCache','ShaderCache',
                         'GraphiteDawnCache','DawnGraphiteCache','DawnWebGPUCache','Media Cache',
                         'Component_CrxCache','Optimization Guide Model Store','optimization_guide_model_store')
$browsers = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data",
    "$env:LOCALAPPDATA\Google\Chrome\USER",
    "$env:LOCALAPPDATA\ChromeAccountProfiles",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
    "$env:LOCALAPPDATA\Microsoft\Edge"
)
foreach ($bd in $browsers) {
    if (-not (Test-Path $bd)) { continue }
    $bname = Split-Path $bd -Leaf
    Get-ChildItem -LiteralPath $bd -Directory -EA SilentlyContinue | ForEach-Object {
        foreach ($sub in $browserCacheSubdirs) {
            Clear-Inside ("{0} {1} {2}" -f $bname, $_.Name, $sub) (Join-Path $_.FullName $sub)
        }
    }
}
if (-not (Is-Running 'firefox')) {
    Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -EA SilentlyContinue | ForEach-Object {
        Clear-Inside 'Firefox cache2'       (Join-Path $_.FullName 'cache2')
        Clear-Inside 'Firefox startupCache' (Join-Path $_.FullName 'startupCache')
        Clear-Inside 'Firefox shader cache' (Join-Path $_.FullName 'shader-cache')
    }
} else { $results.Add('  skip     Firefox running - cache skipped') }
# Legacy IE/WinInet caches
Clear-Inside 'INetCache'  "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
Clear-Inside 'WebCache'   "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"

#---------------- 5. Windows system junk ----------------
Write-Host ""
Write-Host "[5/9] Windows system junk" -ForegroundColor Yellow
Clear-Inside 'WER report archive'   'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
Clear-Inside 'WER report queue'     'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'
Clear-Older  'Windows WDI trace logs' 'C:\Windows\System32\WDI\LogFiles' 14
Clear-Inside 'Windows SystemTemp'   'C:\Windows\SystemTemp'
Clear-Older  'Windows CBS logs'     'C:\Windows\Logs\CBS' 30
Clear-Older  'Windows DISM logs'    'C:\Windows\Logs\DISM' 30
Clear-Older  'Windows ETL traces'   'C:\Windows\Logs' 30
Clear-Older  'Kernel memory reports' 'C:\Windows\LiveKernelReports' 14
Clear-Older  'Minidumps'            'C:\Windows\Minidump' 14
$dmp = 'C:\Windows\MEMORY.DMP'
if ((Test-Path $dmp) -and ((Get-Item $dmp).LastWriteTime -lt (Get-Date).AddDays(-14))) {
    $sz = (Get-Item $dmp).Length
    Remove-Item $dmp -Force -EA SilentlyContinue
    if ($sz -gt 1MB) { $results.Add(("  {0,8:N0} MB  MEMORY.DMP" -f ($sz/1MB))) }
}
Clear-Inside 'CrashDumps (per-user)' "$env:LOCALAPPDATA\CrashDumps"
Clear-Older  'Defender support logs' 'C:\ProgramData\Microsoft\Windows Defender\Support' 14
Clear-Inside 'Thumbnail cache'       "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -EA SilentlyContinue
Clear-Inside 'Delivery Optimization cache' "$env:LOCALAPPDATA\Microsoft\Windows\DeliveryOptimization\Cache"
Delete-DeliveryOptimizationCache -Force -EA SilentlyContinue
# Windows Update download cache: clear when idle; with -Deep stop services first
if ($Deep) {
    Stop-Service wuauserv,bits,dosvc -Force -EA SilentlyContinue
    Clear-Inside 'Windows Update downloads' 'C:\Windows\SoftwareDistribution\Download'
    Start-Service wuauserv,bits,dosvc -EA SilentlyContinue
} else {
    Clear-Inside 'Windows Update downloads' 'C:\Windows\SoftwareDistribution\Download'
}
# Windows Sandbox session leftovers (only when no sandbox is running)
if (-not (Is-Running 'WindowsSandbox|CmService')) {
    Clear-Inside 'Sandbox session storages' 'C:\ProgramData\Microsoft\Windows\Containers\ContainerStorages'
    Clear-Inside 'Sandbox saved states'     'C:\ProgramData\Microsoft\Windows\Containers\Snapshots'
} else { $results.Add('  skip     Windows Sandbox running') }
# Windows.old (only if present - removed the official DISM way)
if (Test-Path 'C:\Windows.old') {
    Write-Host '  Windows.old found - removing superseded files via DISM...' -ForegroundColor Yellow
    Dism.exe /Online /Cleanup-Image /SPSuperseded /NoPrompt 2>&1 | Out-Null
}

#---------------- 6. App logs / crash dumps ----------------
Write-Host ""
Write-Host "[6/9] App logs and crash dumps" -ForegroundColor Yellow
Clear-Older 'ZCode crash dumps'      "$env:USERPROFILE\.zcode\v2\crash" 3
Clear-Older 'ZCode v2 logs'          "$env:USERPROFILE\.zcode\v2\logs" 3
Clear-Older 'ZCode CLI logs'         "$env:USERPROFILE\.zcode\cli\log" 3
Clear-Inside 'ZCode tmp'             "$env:USERPROFILE\.zcode\tmp"
if (-not $codexRunning) {
    Clear-Inside 'Codex tmp'         "$env:USERPROFILE\.codex\.tmp"
} else { $results.Add('  skip     Codex running - .codex tmp kept') }
Clear-Older 'Plex logs'              "$env:LOCALAPPDATA\Plex Media Server\Logs" 3
Clear-Inside 'Plex cache'            "$env:LOCALAPPDATA\Plex Media Server\Cache"
Clear-Older 'Tailscale logs'         'C:\ProgramData\Tailscale\Logs' 3
Clear-Older 'qBittorrent logs'       "$env:LOCALAPPDATA\qBittorrent\logs" 3
Clear-Inside 'Wand crash dumps'      "$env:LOCALAPPDATA\Wand\dumps"
Clear-Inside 'Ollama server logs'    "$env:LOCALAPPDATA\Ollama\logs"
Clear-Inside 'Ollama server logs (alt)' "$env:LOCALAPPDATA\Ollama\log"
Clear-Inside 'Hydra Launcher redist installers' "$env:APPDATA\hydralauncher\CommonRedist"
Clear-Inside 'Python manager download cache' "$env:LOCALAPPDATA\Python\_cache"
if (-not $codexRunning) {
    Clear-Inside 'Codex installer temp (inno-temp)' "$env:LOCALAPPDATA\Codex\GameAutoInstall\state\inno-temp"
}

#---------------- 7. Dev package caches (all re-download automatically on next use) ----------------
Write-Host ""
Write-Host "[7/9] Dev package caches" -ForegroundColor Yellow
Clear-Inside 'npm cache'           "$env:LOCALAPPDATA\npm-cache\_cacache"
Clear-Inside 'npm logs'            "$env:LOCALAPPDATA\npm-cache\_logs"
Clear-Inside 'pip cache'           "$env:LOCALAPPDATA\pip\cache"
Clear-Inside 'NuGet http cache'    "$env:LOCALAPPDATA\NuGet\v3-cache"
Clear-Inside 'NuGet plugins cache' "$env:LOCALAPPDATA\NuGet\plugins-cache"
Clear-Inside 'NuGet global packages (re-restores on next build)' "$env:USERPROFILE\.nuget\packages"
Clear-Inside 'Gradle caches (re-download on next build)' "$env:USERPROFILE\.gradle\caches"
Clear-Inside 'Yarn cache'          "$env:LOCALAPPDATA\Yarn\Cache"
Clear-Inside 'dush search cache'   "$env:LOCALAPPDATA\dush\cache"
$pnpm = (Get-Command pnpm -EA SilentlyContinue).Source
if (-not $pnpm) { $pnpm = 'C:\ProgramData\chocolatey\bin\pnpm.exe' }
if (Test-Path $pnpm) { & $pnpm store prune 2>&1 | Out-Null; $results.Add('  pruned   pnpm store (unreferenced packages)') }
if (-not $codexRunning) {
    Remove-Folder 'Codex runtime cache (re-provisions on next run)' "$env:USERPROFILE\.cache\codex-runtimes"
} else { $results.Add('  skip     Codex running - codex-runtimes kept') }
Remove-Folder 'Playwright browsers (re-download on demand)' "$env:LOCALAPPDATA\ms-playwright"

#---------------- 8. Recycle bin + shadow copies ----------------
Write-Host ""
Write-Host "[8/9] Recycle bin / shadow copies" -ForegroundColor Yellow
Clear-RecycleBin -DriveLetter C -Force -EA SilentlyContinue
if ($Shadows) {
    vssadmin delete shadows /for=C: /all /quiet 2>&1 | Out-Null
    vssadmin resize shadowstorage /for=C: /on=C: /maxsize=5GB 2>&1 | Out-Null
    $results.Add('  deleted  all restore points (future usage capped at 5 GB)')
} else {
    # keep the NEWEST restore point, let Windows prune older ones to fit 10 GB
    vssadmin resize shadowstorage /for=C: /on=C: /maxsize=10GB 2>&1 | Out-Null
    $results.Add('  capped   restore-point storage at 10 GB (newest restore point kept)')
}

#---------------- 9. DEEP: WinSxS component store ----------------
if ($Deep) {
    Write-Host ""
    Write-Host "[9/9] DEEP: DISM component store cleanup (a few minutes)..." -ForegroundColor Yellow
    Dism.exe /Online /Cleanup-Image /StartComponentCleanup /NoPrompt 2>&1 | Out-Null
    $results.Add('  deep     DISM StartComponentCleanup executed')
}

#---------------- summary ----------------
$free1 = (Get-PSDrive C).Free
$freed = $free1 - $free0
$sw.Stop()

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
$results | ForEach-Object { Write-Host $_ }
Write-Host "---------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ("  FREED THIS RUN : {0:N2} GB" -f ($freed/$GB)) -ForegroundColor Green
Write-Host ("  Free now       : {0:N2} GB   (was {1:N2} GB)" -f ($free1/$GB), ($free0/$GB)) -ForegroundColor Green
Write-Host ("  Elapsed        : {0:N0} s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Cyan

("=== Daily-Cleanup {0}  freed {1} GB ===" -f (Get-Date -Format s), [Math]::Round($freed/$GB,2)) | Out-File $logFile -Encoding utf8
$results | Out-File $logFile -Append -Encoding utf8
Write-Host "Log saved: $logFile"
# when the script elevated itself into a new window, keep it open so the report is visible
if ($PauseAtEnd) {
    Write-Host ""
    Write-Host "Press Enter to close this window..." -ForegroundColor Cyan
    [void](Read-Host)
}
