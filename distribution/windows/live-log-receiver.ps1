param(
    [int]$Port = 19191,
    [string]$BindAddress = "0.0.0.0"
)

$endpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($BindAddress), $Port)
$udp = [System.Net.Sockets.UdpClient]::new($endpoint)

Write-Host "[MeloNX] Live log receiver started on ${BindAddress}:${Port}"
Write-Host "[MeloNX] Press Ctrl+C to stop."

try {
    while ($true) {
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        $bytes = $udp.Receive([ref]$remote)
        $line = [System.Text.Encoding]::UTF8.GetString($bytes)
        $prefix = "[{0}] [{1}:{2}]" -f (Get-Date -Format "HH:mm:ss"), $remote.Address, $remote.Port
        Write-Host "$prefix $line" -NoNewline
    }
}
finally {
    $udp.Close()
}
