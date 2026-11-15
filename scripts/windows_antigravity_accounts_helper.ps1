param([ValidateSet('launch','quota')][string]$Action, [string]$Root, [string]$AccountId,
    [string]$ExePath, [string]$ResultPath, [string]$WorkspaceHome = '', [switch]$Library)
$ErrorActionPreference = 'Stop'

function Get-ProfilePath {
    if ($AccountId -ne 'default' -and $AccountId -cnotmatch '^[a-f0-9]{32}$') { throw '账号标识无效。' }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $path = [IO.Path]::GetFullPath((Join-Path $base $AccountId))
    if (-not $path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw '账号路径无效。' }
    return $path
}

function Get-LaunchInfo([string]$Path) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $ExePath
    $info.WorkingDirectory = [IO.Path]::GetDirectoryName($ExePath)
    $info.UseShellExecute = $false
    if ($AccountId -ne 'default') {
        $data = Join-Path $Path 'data'
        $userDirectory = Join-Path $Path 'home'
        [void][IO.Directory]::CreateDirectory($data)
        [void][IO.Directory]::CreateDirectory($userDirectory)
        $info.Arguments = '--user-data-dir="' + $data + '" --new-window'
        # Child-only environment: separate editor state and backend file-token storage.
        # Remote-session compatibility makes the backend use files under this home.
        $info.EnvironmentVariables['USERPROFILE'] = $userDirectory
        $info.EnvironmentVariables['SSH_CONNECTION'] = '127.0.0.1 1234 127.0.0.1 22'
        $info.EnvironmentVariables['SSH_CLIENT'] = '127.0.0.1 1234 22'
    }
    return $info
}

function Test-ProfileEditor($Process, [string]$ProfilePath) {
    if ($Process.Name -notin @('Antigravity.exe','Antigravity IDE.exe') -or [string]::IsNullOrWhiteSpace($Process.CommandLine) -or $Process.CommandLine -match '--type[=\s]') { return $false }
    $match = [regex]::Match($Process.CommandLine, '--user-data-dir(?:=|\s+)(?:"([^"]+)"|([^\s]+))')
    if ($AccountId -eq 'default') { return -not $match.Success }
    if (-not $match.Success) { return $false }
    $actual = $match.Groups[1].Value
    if (-not $actual) { $actual = $match.Groups[2].Value }
    try { return [IO.Path]::GetFullPath($actual).TrimEnd('\').Replace('/','\') -eq [IO.Path]::GetFullPath((Join-Path $ProfilePath 'data')).TrimEnd('\').Replace('/','\') } catch { return $false }
}

function Start-DetachedEditor($Info) {
    # A launched editor must outlive the short-lived helper and its output pipes.
    # Do not let the Electron console inherit Godot's helper stdout/stderr handles.
    if (-not ('HexagonDetachedProcess' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HexagonDetachedProcess {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct STARTUPINFO { public int cb; public string reserved, desktop, title; public int x,y,w,h,cx,cy,fill,flags; public short show,reserved2; public IntPtr data,input,output,error; }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESSINFO { public IntPtr process,thread; public int pid,tid; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CreateProcess(string app, System.Text.StringBuilder command, IntPtr pa, IntPtr ta, bool inherit, int flags, IntPtr env, string cwd, ref STARTUPINFO startup, out PROCESSINFO result);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    public static int Start(string app, string args, string env, string cwd) {
        var startup = new STARTUPINFO(); startup.cb = Marshal.SizeOf(startup);
        PROCESSINFO result;
        var block = Marshal.StringToHGlobalUni(env);
        try {
            if (!CreateProcess(app, new System.Text.StringBuilder("\"" + app + "\" " + args), IntPtr.Zero, IntPtr.Zero, false, 0x408, block, cwd, ref startup, out result))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            CloseHandle(result.process); CloseHandle(result.thread); return result.pid;
        } finally { Marshal.FreeHGlobal(block); }
    }
}


'@
    }
    $environment = @($Info.EnvironmentVariables.Keys | Sort-Object | ForEach-Object { [string]$_ + '=' + [string]$Info.EnvironmentVariables[$_] }) -join [char]0
    return [HexagonDetachedProcess]::Start($Info.FileName, $Info.Arguments, ($environment + [char]0 + [char]0), $Info.WorkingDirectory)
}

function Prepare-AccountWorkspace([string]$Profile) {
    if ($AccountId -eq 'default') { return @{shared=$true} }
    . (Join-Path $PSScriptRoot 'windows_antigravity_workspace_helper.ps1')
    $originalHome = $WorkspaceHome
    if (-not $originalHome) { $originalHome = [Environment]::GetFolderPath('UserProfile') }
    $ready = Test-SharedWorkspace $Profile $originalHome
    $targetData = Join-Path $Profile 'data'
    $processes = @(Get-CimInstance Win32_Process)
    $targets = @($processes | Where-Object { Test-ProfileEditor $_ $Profile })
    if (-not $ready) {
        # Close only this profile before relocating its old private databases.
        # Never force a window past an unsaved-file prompt.
        $ids = New-Object 'Collections.Generic.HashSet[int]'
        foreach ($process in $targets) { [void]$ids.Add([int]$process.ProcessId) }
        for ($depth=0; $depth -lt 12; $depth++) {
            foreach ($process in $processes) { if ($ids.Contains([int]$process.ParentProcessId)) { [void]$ids.Add([int]$process.ProcessId) } }
        }
        foreach ($process in $targets) {
            $window = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
            if ($window -and $window.MainWindowHandle -ne 0) { [void]$window.CloseMainWindow() }
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(8)
        do {
            $running = @($ids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
            if ($running.Count -eq 0) { break }
            Start-Sleep -Milliseconds 150
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($running.Count -gt 0) { throw '请保存并退出此账号的 Antigravity 窗口，再重试切换；旧项目和对话仍保留在原目录，未迁移。' }
        # Elevated/unreadable processes may not appear in the profile inventory.
        # Check this profile's editor and database locks rather than blocking on
        # an unrelated default window that is allowed to keep using shared data.
        foreach ($lockPath in @((Join-Path $targetData 'lockfile'),(Join-Path $Profile 'home\.gemini\antigravity\conversation_summaries.db'),(Join-Path $Profile 'home\.gemini\antigravity\conversation_summaries.db-wal'))) {
            if ([IO.File]::Exists($lockPath)) {
                try { $handle = [IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None); $handle.Dispose() }
                catch { throw '此账号的工作区文件仍被占用或无权限读取。请保存并退出此账号的 Antigravity，再重试；其他账号和原始数据不会被强制关闭或覆盖。' }
            }
        }
        Initialize-SharedWorkspace $Profile $originalHome
    }
    # Seed only workspace/navigation UI, never another account's login fields.
    if ($targets.Count -eq 0 -or -not $ready) {
        $previous = 'default'
        $index = Join-Path $Root 'index.json'
        if ([IO.File]::Exists($index)) { $previous = [string](([IO.File]::ReadAllText($index) | ConvertFrom-Json).selected) }
        $sourceData = Join-Path $env:APPDATA 'Antigravity'
        if ($previous -cmatch '^[a-f0-9]{32}$' -and ($ready -or $previous -ne $AccountId)) { $sourceData = Join-Path $Root ($previous + '\data') }
        Copy-WorkspaceUi $sourceData $targetData
    }
    return @{shared=$true}
}

function Convert-Quota($Response) {
    $status = $Response.userStatus
    $models = @()
    foreach ($model in $status.cascadeModelConfigData.clientModelConfigs) {
        $quota = $model.quotaInfo
        if (-not $quota -or $null -eq $quota.remainingFraction) { continue }
        $fraction = 0.0
        if (-not [double]::TryParse([string]$quota.remainingFraction, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$fraction)) { continue }
        if ($fraction -lt 0 -or $fraction -gt 1) { continue }
        $models += @{ name = [string]$model.label; remaining = [math]::Round($fraction * 100, 1); reset = [string]$quota.resetTime }
    }
    if ($models.Count -eq 0) {
        if ($status.email) { return @{ok=$false; logged_in=$true; email=[string]$status.email; message='已识别账号登录，但当前接口未返回可识别的模型额度。'} }
        throw '当前版本未返回可识别的模型额度，额度未知。'
    }
    return @{ ok = $true; logged_in = $true; models = $models; email = [string]$status.email; checked_at = [DateTime]::UtcNow.ToString('o'); message = '登录状态和额度已更新。' }
}

function Get-QuotaDiscoveryFailure($Processes, [string]$ProfilePath, [int]$ProfileServers, [int]$TokenServers) {
    $editors = @($Processes | Where-Object { Test-ProfileEditor $_ $ProfilePath })
    $unreadable = @($Processes | Where-Object { ($_.Name -like 'language_server*' -or $_.Name -in @('Antigravity.exe','Antigravity IDE.exe')) -and [string]::IsNullOrWhiteSpace($_.CommandLine) })
    if ($TokenServers -gt 0) { return $null }
    if ($ProfileServers -gt 0) {
        return @{ok=$false; editor_running=$true; discovery='unsupported_arguments'; message='已找到此账号的语言服务，但无法识别其本地接口参数。当前 Antigravity 版本可能不兼容，额度未知。'}
    }
    if ($editors.Count -eq 0 -and $unreadable.Count -gt 0) {
        return @{ok=$false; discovery='process_access_denied'; message='存在无法读取启动参数的 Antigravity 进程，无法确认其账号归属。请让 HexagonProxy 与 Antigravity 使用相同权限运行后重试。未将其他账号的额度计入此账号。'}
    }
    if ($editors.Count -eq 0) {
        return @{ok=$false; editor_running=$false; discovery='profile_not_running'; message='此账号的独立窗口未运行；检测到的其他 Antigravity 窗口不属于此配置。请点击此账号旁的“切换”，等待对应窗口启动后刷新。已保存的登录记录不代表窗口正在运行。'}
    }
    if ($unreadable.Count -gt 0) {
        return @{ok=$false; editor_running=$true; discovery='process_access_denied'; message='此账号窗口正在运行，但存在无法读取的语言服务或子进程。请让两个程序使用相同权限运行，再刷新额度。'}
    }
    return @{ok=$false; editor_running=$true; discovery='server_not_started'; message='此账号窗口正在运行，但尚未找到属于它的语言服务。请等待启动完成、打开一个项目并完成登录后刷新；也可查看 Antigravity 自身是否报告语言服务启动失败。'}
}

function Read-Quota([string]$ProfilePath) {
    if (-not ('HexagonLocalCertificate' -as [type])) {
        Add-Type -TypeDefinition @'
public static class HexagonLocalCertificate {
    public static readonly System.Net.Security.RemoteCertificateValidationCallback Check =
        (sender, cert, chain, errors) => sender is System.Net.HttpWebRequest &&
        ((System.Net.HttpWebRequest)sender).RequestUri.IsLoopback;
}
'@
    }
    $processes = @(Get-CimInstance Win32_Process)
    $profileServerCount = 0
    $matchingCount = 0
    $attemptCount = 0
    $lastFailure = ''
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $exeDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ExePath)).TrimEnd('\') + '\'
    $servers = @($processes | Where-Object { $_.Name -like 'language_server*' -and $_.ExecutablePath -and $_.ExecutablePath.StartsWith($exeDirectory, [StringComparison]::OrdinalIgnoreCase) })
    foreach ($server in $servers) {
        # Bind a language server to the selected editor's process ancestry.
        $ancestor = $server
        $matchesProfile = $false
        for ($depth = 0; $depth -lt 12 -and $ancestor; $depth++) {
            $matchesProfile = Test-ProfileEditor $ancestor $ProfilePath
            if ($matchesProfile) { break }
            $parentId = $ancestor.ParentProcessId
            $ancestor = $processes | Where-Object { $_.ProcessId -eq $parentId } | Select-Object -First 1
        }
        if (-not $matchesProfile) { continue }
        $profileServerCount++
        $tokenMatch = [regex]::Match([string]$server.CommandLine, '--csrf_token(?:=|\s+)(?:"([^"]+)"|([^\s"]+))')
        if (-not $tokenMatch.Success) { continue }
        $matchingCount++
        $csrf = if ($tokenMatch.Groups[1].Success) { $tokenMatch.Groups[1].Value } else { $tokenMatch.Groups[2].Value }
        $ports = @(Get-NetTCPConnection -OwningProcess $server.ProcessId -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort -Unique | Select-Object -First 4)
        foreach ($port in $ports) {
          foreach ($scheme in @('https','http')) {
            if ([DateTime]::UtcNow -ge $deadline) { break }
            $attemptCount++
            try {
                $request = [Net.HttpWebRequest]::Create("${scheme}://127.0.0.1:$port/exa.language_server_pb.LanguageServerService/GetUserStatus")
                if ($scheme -eq 'https') { $request.ServerCertificateValidationCallback = [HexagonLocalCertificate]::Check }
                $request.Proxy = $null
                $request.AllowAutoRedirect = $false
                $request.Timeout = 1500; $request.ReadWriteTimeout = 1500
                $request.Method = 'POST'; $request.ContentType = 'application/json'
                $request.Headers['x-codeium-csrf-token'] = $csrf
                $request.Headers['Connect-Protocol-Version'] = '1'
                $bytes = [Text.Encoding]::UTF8.GetBytes('{"metadata":{"ideName":"antigravity","extensionName":"antigravity","ideVersion":"unknown","locale":"en"}}')
                $request.ContentLength = $bytes.Length
                $stream = $request.GetRequestStream(); $stream.Write($bytes,0,$bytes.Length); $stream.Dispose()
                $response = $request.GetResponse()
                $reader = New-Object IO.StreamReader($response.GetResponseStream())
                try { $body = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose(); $response.Dispose() }
                $quotaResult = Convert-Quota $body
                $quotaResult.editor_running = $true
                return $quotaResult
            } catch {
                # Do not include request headers, command lines or tokens in errors.
                $lastFailure = $_.Exception.GetType().Name
                if ($_.Exception -is [Net.WebException]) { $lastFailure = [string]$_.Exception.Status }
                if ($_.Exception.Message -like '*未返回可识别*') { $lastFailure = '接口未返回可识别的模型额度' }
            }
          }
        }
    }
    $discoveryFailure = Get-QuotaDiscoveryFailure $processes $ProfilePath $profileServerCount $matchingCount
    if ($discoveryFailure) { return $discoveryFailure }
    throw "所选账号的本地额度接口查询失败（尝试 $attemptCount 次；$lastFailure）。请检查登录状态，或当前 Antigravity 版本的接口兼容性。"
}

function Invoke-AccountAction {
    $path = Get-ProfilePath
    if ($Action -eq 'quota') { return Read-Quota $path }
    if (-not [IO.File]::Exists($ExePath) -or [IO.Path]::GetFileName($ExePath) -notin @('Antigravity.exe','Antigravity IDE.exe')) { throw '未找到 Antigravity，请先选择程序。' }
    $workspace = Prepare-AccountWorkspace $path
    # Existing windows remain intact. Each profile has an independent data directory.
    $info = Get-LaunchInfo $path
    $editorId = Start-DetachedEditor $info
    $process = Get-Process -Id $editorId -ErrorAction SilentlyContinue
    if ($process -and $process.WaitForExit(400)) {
        $exitCode = $process.ExitCode
        # Electron's second-instance handoff can finish before Get-Process binds
        # its exit handle; PowerShell then exposes null rather than an exit code.
        if ($null -ne $exitCode -and $exitCode -ne 0) { throw "Antigravity 启动失败（退出码 $exitCode）。请检查程序安装和账号目录权限。" }
    }
    return @{ ok = $true; workspace_shared = [bool]$workspace.shared; message = '已打开目标账号，继续使用共享的项目和对话。新账号首次需要完成官方登录。'; pid = $editorId }
}
if ($Library) { return }
try { $result = Invoke-AccountAction } catch { $result = @{ ok = $false; message = $_.Exception.Message } }
$json = $result | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($ResultPath + '.tmp', $json, (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath ($ResultPath + '.tmp') -Destination $ResultPath -Force
