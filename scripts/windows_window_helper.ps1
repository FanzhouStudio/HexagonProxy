param(
    [ValidateSet("hide", "show", "watch")]
    [string]$Action,
    [int]$ProcessId,
    [string]$WindowTitle,
    [string]$CommandPath
)

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class HexagonWindowApi {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

function Invoke-WindowAction([string]$RequestedAction) {
$script:window = [IntPtr]::Zero
$callback = [HexagonWindowApi+EnumWindowsProc]{
    param([IntPtr]$handle, [IntPtr]$state)
    $ownerPid = [uint32]0
    [void][HexagonWindowApi]::GetWindowThreadProcessId($handle, [ref]$ownerPid)
    if ($ownerPid -ne $ProcessId) { return $true }
    $title = New-Object System.Text.StringBuilder 256
    [void][HexagonWindowApi]::GetWindowText($handle, $title, $title.Capacity)
    if ($title.ToString().StartsWith($WindowTitle, [System.StringComparison]::Ordinal)) {
        $script:window = $handle
        return $false
    }
    return $true
}

[void][HexagonWindowApi]::EnumWindows($callback, [IntPtr]::Zero)
if ($window -eq [IntPtr]::Zero) { return }

if ($RequestedAction -eq "hide") {
    [void][HexagonWindowApi]::ShowWindowAsync($window, 0)
} else {
    [void][HexagonWindowApi]::ShowWindowAsync($window, 9)
    [void][HexagonWindowApi]::SetForegroundWindow($window)
}
}

if ($Action -ne 'watch') { Invoke-WindowAction $Action; exit }
# One prewarmed bridge per application. Read the latest desired state, so rapid
# hide/show clicks cannot leave independently spawned helpers racing each other.
$parent = Get-Process -Id $ProcessId -ErrorAction Stop
$watcher = New-Object IO.FileSystemWatcher ([IO.Path]::GetDirectoryName($CommandPath)), ([IO.Path]::GetFileName($CommandPath))
$watcher.EnableRaisingEvents = $true
$previous = ''
try {
    while (-not $parent.HasExited) {
        if ([IO.File]::Exists($CommandPath)) {
            try {
                $command = [IO.File]::ReadAllText($CommandPath).Trim()
                $parts = $command -split '\|', 2
                if ($parts.Length -eq 2 -and $parts[1] -in @('hide','show') -and $command -ne $previous) {
                    Invoke-WindowAction $parts[1]
                    $previous = $command
                }
            } catch { }
        }
        [void]$watcher.WaitForChanged([IO.WatcherChangeTypes]::All, 200)
    }
} finally { $watcher.Dispose(); $parent.Dispose() }
