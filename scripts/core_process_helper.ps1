param(
    [Parameter(Mandatory = $true)]
    [string]$CorePath
)

$ErrorActionPreference = 'Stop'
$expectedPath = [System.IO.Path]::GetFullPath($CorePath)
$processes = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue

foreach ($process in $processes) {
    if ([string]::Equals([string]$process.Path, $expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Process -Id ([int]$process.Id) -Force -ErrorAction Stop
    }
}

$deadline = [DateTime]::UtcNow.AddSeconds(5)
do {
    $remaining = @(
        Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue |
            Where-Object { [string]::Equals([string]$_.Path, $expectedPath, [System.StringComparison]::OrdinalIgnoreCase) }
    )
    if ($remaining.Count -eq 0) {
        exit 0
    }
    Start-Sleep -Milliseconds 100
} while ([DateTime]::UtcNow -lt $deadline)

exit 1
