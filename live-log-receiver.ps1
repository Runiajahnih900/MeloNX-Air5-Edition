param(
    [int]$Port = 19191,
    [string]$BindAddress = "0.0.0.0",
    [string]$OutputDirectory = "live-log-sessions",
    [switch]$SingleSessionFile
)

$endpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($BindAddress), $Port)
$udp = [System.Net.Sockets.UdpClient]::new($endpoint)

if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $resolvedOutputDirectory = $OutputDirectory
} else {
    $resolvedOutputDirectory = Join-Path (Get-Location) $OutputDirectory
}

[System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null

$script:sessionWriter = $null
$script:sessionCounter = 0

function Start-NewSessionLog {
    param(
        [System.Net.IPEndPoint]$Remote,
        [string]$Reason
    )

    if ($script:sessionWriter -ne $null) {
        $script:sessionWriter.Flush()
        $script:sessionWriter.Dispose()
        $script:sessionWriter = $null
    }

    $script:sessionCounter++

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $remoteTag = if ($Remote -ne $null) { $Remote.Address.ToString().Replace(":", "-") } else { "unknown" }
    $fileName = "MeloNX-LiveLog-${timestamp}-${remoteTag}-S{0:D3}.log" -f $script:sessionCounter
    $sessionPath = Join-Path $resolvedOutputDirectory $fileName

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $script:sessionWriter = [System.IO.StreamWriter]::new($sessionPath, $false, $utf8NoBom)
    $script:sessionWriter.AutoFlush = $true

    Write-Host "[MeloNX] Recording session #$($script:sessionCounter): $sessionPath"
    Write-Host "[MeloNX] Session rollover reason: $Reason"
}

Write-Host "[MeloNX] Live log receiver started on ${BindAddress}:${Port}"
Write-Host "[MeloNX] Logs will be saved to: $resolvedOutputDirectory"
Write-Host "[MeloNX] Press Ctrl+C to stop."

try {
    while ($true) {
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        $bytes = $udp.Receive([ref]$remote)
        $line = [System.Text.Encoding]::UTF8.GetString($bytes)

        $isSessionStart = $line -match "(?m)^\s*Session started:"
        if ($script:sessionWriter -eq $null) {
            Start-NewSessionLog -Remote $remote -Reason "first packet"
        } elseif (-not $SingleSessionFile.IsPresent -and $isSessionStart) {
            Start-NewSessionLog -Remote $remote -Reason "session marker detected"
        }

        $prefix = "[{0}] [{1}:{2}]" -f (Get-Date -Format "HH:mm:ss"), $remote.Address, $remote.Port
        $entry = "$prefix $line"

        Write-Host $entry -NoNewline
        $script:sessionWriter.Write($entry)
    }
}
finally {
    if ($script:sessionWriter -ne $null) {
        $script:sessionWriter.Flush()
        $script:sessionWriter.Dispose()
    }

    $udp.Close()
}
