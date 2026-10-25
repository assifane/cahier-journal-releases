param([Parameter(Mandatory=$true)][string]$FilePath,[Parameter(Mandatory=$true)][string]$ReleasePath,[Parameter(Mandatory=$true)][string]$ReadyPath)
$ErrorActionPreference = 'Stop'
$heldFile = $null
$deadline = (Get-Date).AddSeconds(30)
while (-not $heldFile -and (Get-Date) -lt $deadline) {
    try { $heldFile = [System.IO.File]::Open($FilePath,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::None) }
    catch { Start-Sleep -Milliseconds 200 }
}
if (-not $heldFile) { exit 2 }
try {
    @{ holding=$true; pid=$PID } | ConvertTo-Json | Set-Content -Encoding ASCII -LiteralPath $ReadyPath
    [Console]::Out.WriteLine('LOCKED')
    [Console]::Out.Flush()
    $releaseDeadline = (Get-Date).AddMinutes(5)
    while (-not (Test-Path -LiteralPath $ReleasePath) -and (Get-Date) -lt $releaseDeadline) { Start-Sleep -Milliseconds 100 }
} finally { $heldFile.Dispose() }
