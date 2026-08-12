param(
    [ValidateSet("hide", "show")]
    [string]$Action,
    [int]$ProcessId,
    [string]$WindowTitle
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

$window = [IntPtr]::Zero
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
if ($window -eq [IntPtr]::Zero) { exit 2 }

if ($Action -eq "hide") {
    [void][HexagonWindowApi]::ShowWindowAsync($window, 0)
} else {
    [void][HexagonWindowApi]::ShowWindowAsync($window, 9)
    Start-Sleep -Milliseconds 80
    [void][HexagonWindowApi]::SetForegroundWindow($window)
}
