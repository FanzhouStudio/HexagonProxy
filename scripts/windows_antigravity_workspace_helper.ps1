$ErrorActionPreference = 'Stop'

function Get-CanonicalPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\').Replace('/','\')
}

function Assert-PlainDirectory([string]$Path) {
    # Never migrate through an unexpected junction or symlink.
    $current = $Path
    while ($current) {
        if ([IO.Directory]::Exists($current)) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '共享数据路径包含未知链接，已停止迁移，请检查目录。' }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Copy-MissingWorkspaceFiles([string]$Source, [string]$Target) {
    [void][IO.Directory]::CreateDirectory($Target)
    foreach ($entry in Get-ChildItem -LiteralPath $Source -Force) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '旧数据包含未知链接，已保留原目录并停止迁移。' }
        $destination = Join-Path $Target $entry.Name
        if ($entry.PSIsContainer) {
            if ([IO.File]::Exists($destination)) { throw '共享数据中存在同名文件和目录，已停止迁移。' }
            Copy-MissingWorkspaceFiles $entry.FullName $destination
        } elseif (-not [IO.File]::Exists($destination)) {
            [IO.File]::Copy($entry.FullName, $destination, $false)
        }
    }
}

function Initialize-WorkspaceSqlite {
    if ('HexagonWorkspaceSqlite' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class HexagonWorkspaceSqlite {
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Row(IntPtr p,int n,IntPtr values,IntPtr names);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Unicode)] static extern int sqlite3_open16(string name,out IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db,int ms);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_exec(IntPtr db,byte[] sql,Row callback,IntPtr arg,out IntPtr error);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern void sqlite3_free(IntPtr p);
    static string Text(IntPtr ptr) { if(ptr==IntPtr.Zero)return ""; int n=0; while(Marshal.ReadByte(ptr,n)!=0)n++; var b=new byte[n]; Marshal.Copy(ptr,b,0,n); return Encoding.UTF8.GetString(b); }
    public static string[][] Exec(string path,string sql) {
        IntPtr db; int rc=sqlite3_open16(path,out db);
        if(rc!=0) { if(db!=IntPtr.Zero)sqlite3_close(db); throw new Exception("SQLite open failed: "+rc); }
        try {
            sqlite3_busy_timeout(db,3000);
            var rows=new List<string[]>();
            Row callback=(p,n,v,names)=> {var row=new string[n];for(int i=0;i<n;i++)row[i]=Text(Marshal.ReadIntPtr(v,i*IntPtr.Size)); rows.Add(row);return 0;};
            IntPtr error; rc=sqlite3_exec(db,Encoding.UTF8.GetBytes(sql+"\0"),callback,IntPtr.Zero,out error);
            if(error!=IntPtr.Zero)sqlite3_free(error);
            if(rc!=0)throw new Exception("SQLite operation failed: "+rc);
            return rows.ToArray();
        } finally {sqlite3_close(db);}
    }
}
'@
}

function Merge-ConversationIndex([string]$Source, [string]$Target) {
    if (-not [IO.File]::Exists($Source)) { return }
    Initialize-WorkspaceSqlite
    $escaped = $Source.Replace("'", "''")
    if (-not [IO.File]::Exists($Target)) {
        # The profile is stopped, so its SQLite main file and WAL are stable.
        [void][HexagonWorkspaceSqlite]::Exec($Source, 'PRAGMA wal_checkpoint(TRUNCATE);')
        [IO.File]::Copy($Source, $Target, $false)
        return
    }
    # Merge indexes transactionally; never replace an existing conversation row.
    # Full-text search remains owned/rebuilt by Antigravity, not copied piecemeal.
    $sql = "ATTACH DATABASE '$escaped' AS legacy; BEGIN IMMEDIATE;"
    foreach ($table in @('conversation_summaries','conversation_parents')) {
        $sourceTables = [HexagonWorkspaceSqlite]::Exec($Source, "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';")
        $targetTables = [HexagonWorkspaceSqlite]::Exec($Target, "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';")
        if ($sourceTables.Length -eq 0) { continue }
        if ($targetTables.Length -eq 0) { throw '对话索引结构不一致，已保留旧账号数据，请更新 Antigravity 后重试。' }
        $sourceColumns = [HexagonWorkspaceSqlite]::Exec($Source, "PRAGMA table_info('$table');")
        $targetColumns = [HexagonWorkspaceSqlite]::Exec($Target, "PRAGMA table_info('$table');")
        $names = @($sourceColumns | ForEach-Object { $_[1] })
        $columns = @($targetColumns | Where-Object { $names -contains $_[1] } | ForEach-Object { '"' + $_[1].Replace('"','""') + '"' }) -join ','
        if (-not $columns -or $names -notcontains 'conversation_id') { throw '无法识别旧对话索引，已停止迁移。' }
        $sql += "INSERT OR IGNORE INTO main.$table ($columns) SELECT $columns FROM legacy.$table;"
        # OR IGNORE is for duplicate IDs only. A newer schema must not silently
        # discard a nonduplicate legacy row because of another constraint.
        $sql += "CREATE TEMP TABLE merge_guard(n INTEGER CHECK(n=0)); INSERT INTO merge_guard SELECT COUNT(*) FROM legacy.$table l LEFT JOIN main.$table m ON l.conversation_id=m.conversation_id WHERE m.conversation_id IS NULL; DROP TABLE merge_guard;"
    }
    $sql += 'COMMIT; DETACH DATABASE legacy;'
    [void][HexagonWorkspaceSqlite]::Exec($Target, $sql)
}

function Connect-SharedDirectory([string]$Local, [string]$Shared, [bool]$Conversations) {
    $localFull = Get-CanonicalPath $Local
    $sharedFull = Get-CanonicalPath $Shared
    if ($localFull -eq $sharedFull -or $sharedFull.StartsWith($localFull + '\', [StringComparison]::OrdinalIgnoreCase) -or $localFull.StartsWith($sharedFull + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '共享目录与账号目录重叠，已取消。' }
    $marker = $localFull + '.sharing.json'
    if ([IO.File]::Exists($marker)) {
        $saved = [IO.File]::ReadAllText($marker) | ConvertFrom-Json
        $savedBackup = Get-CanonicalPath ([string]$saved.backup)
        if (-not $savedBackup.StartsWith($localFull + '.before-sharing-', [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetDirectoryName($savedBackup) -ne [IO.Path]::GetDirectoryName($localFull) -or (Get-CanonicalPath ([string]$saved.target)) -ne $sharedFull) { throw '共享迁移恢复记录无效，已保留备份。' }
        if (-not [IO.Directory]::Exists($Local) -and [IO.Directory]::Exists($savedBackup)) {
            Assert-PlainDirectory $savedBackup
            [IO.Directory]::Move($savedBackup, $localFull)
        } elseif ([IO.Directory]::Exists($savedBackup) -and [IO.Directory]::Exists($Local) -and -not ((Get-Item -LiteralPath $Local -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw '检测到未完成的工作区恢复，原目录和备份均已保留，请先核对恢复后再切换。'
        }
        [IO.File]::Delete($marker)
    }
    Assert-PlainDirectory $Shared
    [void][IO.Directory]::CreateDirectory($Shared)
    if ([IO.Directory]::Exists($Local)) {
        $item = Get-Item -LiteralPath $Local -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if ($item.LinkType -ne 'Junction' -or (Get-CanonicalPath ([string]@($item.Target)[0])) -ne $sharedFull) { throw '账号数据已有其他目录链接，已停止更改。' }
            return
        }
        Assert-PlainDirectory $Local
        $backup = $localFull + '.before-sharing-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')
        # Both paths are verified siblings under the same profile parent.
        if ([IO.Path]::GetDirectoryName($backup) -ne [IO.Path]::GetDirectoryName($localFull)) { throw '备份路径无效。' }
        [IO.File]::WriteAllText($marker, (@{backup=$backup;target=$sharedFull} | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        try { [IO.Directory]::Move($localFull, $backup) }
        catch { [IO.File]::Delete($marker); throw '该账号的后台插件仍在使用旧工作区目录，请保存并完整退出该账号及后台进程后重试。原项目、对话和登录均未替换。' }
        try {
            if ($Conversations) {
                foreach ($name in @('conversations','brain','annotations','plugin_data','sidecar_data')) {
                    $directory = Join-Path $backup $name
                    if ([IO.Directory]::Exists($directory)) { Copy-MissingWorkspaceFiles $directory (Join-Path $Shared $name) }
                }
                Merge-ConversationIndex (Join-Path $backup 'conversation_summaries.db') (Join-Path $Shared 'conversation_summaries.db')
            } else {
                $projects = Join-Path $backup 'projects'
                if ([IO.Directory]::Exists($projects)) { Copy-MissingWorkspaceFiles $projects (Join-Path $Shared 'projects') }
                foreach ($name in @('config.json','mcp_config.json')) {
                    if ([IO.File]::Exists((Join-Path $backup $name)) -and -not [IO.File]::Exists((Join-Path $Shared $name))) { [IO.File]::Copy((Join-Path $backup $name),(Join-Path $Shared $name),$false) }
                }
            }
            [void](New-Item -ItemType Junction -Path $localFull -Target $sharedFull -ErrorAction Stop)
        }
        catch { [IO.Directory]::Move($backup, $localFull); [IO.File]::Delete($marker); throw }
        [IO.File]::Delete($marker)
    } else {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Local))
        [void](New-Item -ItemType Junction -Path $Local -Target $Shared -ErrorAction Stop)
    }
}

function Initialize-SharedWorkspace([string]$Profile, [string]$OriginalHome) {
    $gemini = Join-Path $Profile 'home\.gemini'
    $original = Join-Path $OriginalHome '.gemini'
    Connect-SharedDirectory (Join-Path $gemini 'antigravity') (Join-Path $original 'antigravity') $true
    Connect-SharedDirectory (Join-Path $gemini 'config') (Join-Path $original 'config') $false
    # .gemini/jetski-standalone-oauth-token remains private to each profile.
}

function Test-SharedWorkspace([string]$Profile, [string]$OriginalHome) {
    foreach ($name in @('antigravity','config')) {
        $path = Join-Path $Profile ('home\.gemini\' + $name)
        if (-not [IO.Directory]::Exists($path)) { return $false }
        $item = Get-Item -LiteralPath $path -Force
        if ($item.LinkType -ne 'Junction' -or (Get-CanonicalPath ([string]@($item.Target)[0])) -ne (Get-CanonicalPath (Join-Path $OriginalHome ('.gemini\' + $name)))) { return $false }
    }
    return $true
}

function Copy-WorkspaceUi([string]$SourceData, [string]$TargetData) {
    $source = Join-Path $SourceData 'app_storage.json'
    $target = Join-Path $TargetData 'app_storage.json'
    if ((Get-CanonicalPath $SourceData) -eq (Get-CanonicalPath $TargetData) -or -not [IO.File]::Exists($source)) { return }
    $from = [IO.File]::ReadAllText($source) | ConvertFrom-Json
    $result = @{}
    if ([IO.File]::Exists($target)) {
        foreach ($property in ([IO.File]::ReadAllText($target) | ConvertFrom-Json).PSObject.Properties) { $result[$property.Name] = $property.Value }
    }
    foreach ($property in $from.PSObject.Properties) {
        if ($property.Name -match '^(lastCreatedProjectId|projectsOrder|new-convo-magic-workspace-selected|new-convo-last-selected-project|antigravity-multi-conversation-layout-v3.*|aux-pane-session|sidebar_collapsed_sections)$') { $result[$property.Name] = $property.Value }
    }
    [void][IO.Directory]::CreateDirectory($TargetData)
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($result | ConvertTo-Json -Depth 40))
    $temporary = $target + '.workspace.tmp'
    [IO.File]::WriteAllBytes($temporary, $bytes)
    if ([IO.File]::Exists($target)) {
        $backup = $target + '.before-workspace-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')
        [IO.File]::Replace($temporary, $target, $backup)
    } else { [IO.File]::Move($temporary, $target) }
}
