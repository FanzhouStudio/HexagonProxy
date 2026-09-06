param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('inspect', 'switch', 'launch')]
    [string]$Action,
    [string]$CodexHome = '',
    [string]$ElectronUserData = ''
)

$ErrorActionPreference = 'Stop'

function Write-Result($Value) {
    $Value | ConvertTo-Json -Compress -Depth 6
}

function Get-CodexPackage {
    return @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-CodexProcesses {
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $path = [string]$_.ExecutablePath
        $path -like '*\WindowsApps\OpenAI.Codex_*\app\ChatGPT.exe' -or
        $path -like '*\AppData\Local\OpenAI\Codex\*\codex.exe' -or
        $path -like '*\AppData\Local\OpenAI\Codex\bin\*\codex.exe'
    })
}
function Stop-Codex {
    $items = @(Get-CodexProcesses)
    foreach ($item in $items) {
        $path = [string]$item.ExecutablePath
        if ($path -like '*\WindowsApps\OpenAI.Codex_*\app\ChatGPT.exe') {
            try {
                $process = Get-Process -Id ([int]$item.ProcessId) -ErrorAction Stop
                if ($process.MainWindowHandle -ne 0) {
                    [void]$process.CloseMainWindow()
                }
            } catch {}
        }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(2)
    do {
        Start-Sleep -Milliseconds 120
        $remaining = @(Get-CodexProcesses)
    } while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)

    foreach ($item in $remaining) {
        try {
            Stop-Process -Id ([int]$item.ProcessId) -Force -ErrorAction Stop
        } catch {}
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(2)
    do {
        Start-Sleep -Milliseconds 100
        $remaining = @(Get-CodexProcesses)
    } while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)

    return ($remaining.Count -eq 0)
}

function Get-CodexExecutable {
    $pkg = Get-CodexPackage
    if ($pkg.Count -eq 0) { return '' }
    $candidate = Join-Path $pkg[0].InstallLocation 'app\ChatGPT.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return ''
}

function Start-CodexProfile([string]$HomePath, [string]$WebPath) {
    if (-not [string]::IsNullOrWhiteSpace($HomePath)) {
        New-Item -ItemType Directory -Force -Path $HomePath | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($WebPath)) {
        New-Item -ItemType Directory -Force -Path $WebPath | Out-Null
    }

    $exe = Get-CodexExecutable
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.UseShellExecute = $false
    if (-not [string]::IsNullOrWhiteSpace($HomePath)) {
        $psi.EnvironmentVariables['CODEX_HOME'] = $HomePath
    } else {
        $psi.EnvironmentVariables.Remove('CODEX_HOME')
    }
    if (-not [string]::IsNullOrWhiteSpace($WebPath)) {
        $psi.EnvironmentVariables['CODEX_ELECTRON_USER_DATA_PATH'] = $WebPath
    } else {
        $psi.EnvironmentVariables.Remove('CODEX_ELECTRON_USER_DATA_PATH')
    }

    try {
        $process = [Diagnostics.Process]::Start($psi)
        if ($null -eq $process) { return $false }
        Start-Sleep -Milliseconds 800
        return ((Get-CodexProcesses).Count -gt 0)
    } catch {
        return $false
    }
}

try {
    $pkg = Get-CodexPackage
    if ($Action -eq 'inspect') {
        Write-Result ([pscustomobject]@{
            ok = $true
            installed = ($pkg.Count -gt 0)
            running = ((Get-CodexProcesses).Count -gt 0)
        })
        exit 0
    }

    if ($pkg.Count -eq 0) {
        Write-Result ([pscustomobject]@{
            ok = $false
            message_code = 'not_installed'
        })
        exit 0
    }

    if ($Action -eq 'switch' -and -not (Stop-Codex)) {
        Write-Result ([pscustomobject]@{
            ok = $false
            message_code = 'stop_failed'
        })
        exit 0
    }

    $launched = Start-CodexProfile $CodexHome $ElectronUserData
    Write-Result ([pscustomobject]@{
        ok = $launched
        launched = $launched
        message_code = if ($launched) { 'launched' } else { 'launch_failed' }
    })
    exit 0
} catch {
    Write-Result ([pscustomobject]@{
        ok = $false
        message_code = 'exception'
        error_type = $_.Exception.GetType().Name
    })
    exit 0
}
