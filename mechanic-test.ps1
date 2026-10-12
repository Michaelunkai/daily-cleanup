# Functional self-test v2 of the core deletion mechanic used by Daily-Cleanup.ps1
$ErrorActionPreference = 'SilentlyContinue'
$test = 'C:\Users\Admin\Scripts\selftest'
Remove-Item $test -Recurse -Force -EA SilentlyContinue
New-Item -ItemType Directory -Force -Path $test | Out-Null

Set-Content "$test\free1.tmp" ('x' * 5MB)
Set-Content "$test\free2.tmp" ('y' * 3MB)
$locked = "$test\locked_in_use.tmp"
Set-Content $locked ('z' * 2MB)
Write-Output ("locked file size on disk: {0} bytes (expected 2097152)" -f (Get-Item $locked).Length)

$stream = [System.IO.File]::Open($locked, 'Open', 'Read', 'None')
Write-Output ("lock held: {0}" -f ($stream -ne $null))

# prove the lock is real: a second exclusive open must fail
$second = [System.IO.File]::Open($locked, 'Open', 'ReadWrite', 'None')
Write-Output ("second exclusive open unexpectedly succeeded: {0} (expected False)" -f ($second -ne $null))
if ($second) { $second.Close() }

# the exact deletion pattern the script uses
Get-ChildItem $test -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue

$free1Gone = -not (Test-Path "$test\free1.tmp")
$free2Gone = -not (Test-Path "$test\free2.tmp")
$lockedStillThere = Test-Path $locked
$lockedLen = if ($lockedStillThere) { (Get-Item $locked).Length } else { -1 }
Write-Output ("free1 deleted: {0}  free2 deleted: {1}" -f $free1Gone, $free2Gone)
Write-Output ("locked file still present: {0}  length: {1}" -f $lockedStillThere, $lockedLen)

$stream.Close()
Start-Sleep -Milliseconds 200
Remove-Item $test -Recurse -Force -EA SilentlyContinue

if ($free1Gone -and $free2Gone -and $lockedStillThere) { Write-Output 'MECHANIC TEST: PASS' } else { Write-Output 'MECHANIC TEST: FAIL' }
