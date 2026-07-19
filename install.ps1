param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Target,

    [switch]$Symlink,
    [switch]$Force,

    [ValidateSet("lean", "full")]
    [string]$Topology = "lean"
)

$ErrorActionPreference = "Stop"

if (-not ("OmsCodex.NativePath" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace OmsCodex {
    public static class NativePath {
        private const uint FileFlagBackupSemantics = 0x02000000;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string fileName,
            uint desiredAccess,
            FileShare shareMode,
            IntPtr securityAttributes,
            FileMode creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile
        );

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandle(
            SafeFileHandle file,
            [Out] StringBuilder path,
            uint pathLength,
            uint flags
        );

        public static string GetFinalDirectoryPath(string path) {
            using (SafeFileHandle handle = CreateFile(
                path,
                0,
                FileShare.ReadWrite | FileShare.Delete,
                IntPtr.Zero,
                FileMode.Open,
                FileFlagBackupSemantics,
                IntPtr.Zero
            )) {
                if (handle.IsInvalid) {
                    throw new IOException(
                        "디렉터리 핸들을 열 수 없습니다.",
                        Marshal.GetExceptionForHR(Marshal.GetHRForLastWin32Error())
                    );
                }
                StringBuilder buffer = new StringBuilder(32768);
                uint length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
                if (length == 0 || length >= (uint)buffer.Capacity) {
                    throw new IOException(
                        "최종 물리 경로를 확인할 수 없습니다.",
                        Marshal.GetExceptionForHR(Marshal.GetHRForLastWin32Error())
                    );
                }
                string result = buffer.ToString();
                if (result.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) {
                    result = @"\\" + result.Substring(8);
                }
                else if (result.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase)) {
                    result = result.Substring(4);
                }
                return Path.GetFullPath(result).TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar
                );
            }
        }
    }
}
"@
}

function Get-CanonicalDirectoryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )) {
        return [OmsCodex.NativePath]::GetFinalDirectoryPath($fullPath)
    }
    return (Resolve-Path -LiteralPath $fullPath).ProviderPath
}

function Get-KstTimestamp {
    $timeZone = [TimeZoneInfo]::FindSystemTimeZoneById("Korea Standard Time")
    $kstNow = [TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $timeZone)
    return $kstNow.ToString("yyyyMMdd-HHmmss")
}

function Resolve-RequiredPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $path = Join-Path -Path $BasePath -ChildPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "필수 경로가 없습니다: $RelativePath"
    }

    return $path
}

function Get-UniquePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $candidate = $BasePath
    $counter = 1
    while ($null -ne (Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue)) {
        $candidate = "$BasePath.$counter"
        $counter++
    }

    return $candidate
}

function New-InstallTempPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    return Get-UniquePath "$Destination.tmp.$PID.$(Get-KstTimestamp)"
}

function Assert-SafeTargetPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $rootPrefix = "$rootFull$([System.IO.Path]::DirectorySeparatorChar)"
    if ($pathFull -ne $rootFull -and -not $pathFull.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "설치 대상 경로가 대상 프로젝트 범위를 벗어납니다: $pathFull"
    }

    $relative = $pathFull.Substring($rootFull.Length).TrimStart(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $segments = @()
    if (-not [string]::IsNullOrWhiteSpace($relative)) {
        $segments = $relative -split '[\\/]'
    }

    $current = $rootFull
    foreach ($segment in @("") + $segments) {
        if (-not [string]::IsNullOrEmpty($segment)) {
            $current = Join-Path -Path $current -ChildPath $segment
        }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            break
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "설치 대상 경로의 symlink/reparse point를 허용하지 않습니다: $current"
        }
    }
}

function Backup-ExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $existing = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        return $null
    }

    $backupPath = Get-UniquePath "$Path.bak.$(Get-KstTimestamp)"
    Move-Item -LiteralPath $Path -Destination $backupPath
    Write-Host "기존 경로를 백업했습니다: $backupPath"
    return $backupPath
}

function New-StagedProjectItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [switch]$UseSymlink
    )

    $tempPath = New-InstallTempPath $Destination
    try {
        if ($UseSymlink) {
            New-Item -ItemType SymbolicLink -Path $tempPath -Target $Source | Out-Null
        }
        else {
            Copy-Item -LiteralPath $Source -Destination $tempPath -Recurse
        }

        return $tempPath
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -Recurse
        }
        throw
    }
}

$repo = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($repo)) {
    $repo = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$repo = [System.IO.Path]::GetFullPath($repo).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)

$targetRoot = [System.IO.Path]::GetFullPath($Target)
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "대상 프로젝트 디렉터리가 없습니다: $targetRoot"
}
Assert-SafeTargetPath -Root $targetRoot -Path $targetRoot
if ($Symlink) {
    $repoCanonical = Get-CanonicalDirectoryPath $repo
    $targetCanonical = Get-CanonicalDirectoryPath $targetRoot
    $repoPrefix = "$repoCanonical$([System.IO.Path]::DirectorySeparatorChar)"
    $targetPrefix = "$targetCanonical$([System.IO.Path]::DirectorySeparatorChar)"
    if (
        $targetCanonical.Equals($repoCanonical, [System.StringComparison]::OrdinalIgnoreCase) -or
        $targetCanonical.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $repoCanonical.StartsWith($targetPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "symlink 설치에서는 원본 저장소와 대상 프로젝트가 같거나 서로 중첩될 수 없습니다."
    }
}

$skillsRoot = Resolve-RequiredPath -BasePath $repo -RelativePath ".agents\skills"
$sourceAgents = Resolve-RequiredPath -BasePath $repo -RelativePath ".codex\agents"
$topologyPath = Resolve-RequiredPath -BasePath $repo -RelativePath ".agents\skills\init-project\references\topology-profiles.json"
$versionPath = Resolve-RequiredPath -BasePath $repo -RelativePath "VERSION"
$version = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION 형식이 올바르지 않습니다: $version"
}
$topologyConfig = Get-Content -LiteralPath $topologyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$selectedTopology = $topologyConfig.topologies.$Topology
if ($null -eq $selectedTopology) {
    throw "알 수 없는 topology입니다: $Topology"
}
$rawAgentNames = $selectedTopology.default_agents
if ($null -eq $rawAgentNames -or $rawAgentNames -is [string] -or $rawAgentNames -isnot [System.Collections.IEnumerable]) {
    throw "topology의 default_agents는 목록이어야 합니다: $Topology"
}
$agentNames = @($rawAgentNames)
if (
    $agentNames.Count -eq 0 -or
    @($agentNames | Where-Object { $_ -isnot [string] -or $_ -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' }).Count -gt 0 -or
    @($agentNames | Select-Object -Unique).Count -ne $agentNames.Count
) {
    throw "topology의 default_agents가 올바르지 않습니다: $Topology"
}
$agentFiles = @($agentNames | ForEach-Object {
    $agentPath = Join-Path -Path $sourceAgents -ChildPath "$_.toml"
    if (-not (Test-Path -LiteralPath $agentPath -PathType Leaf)) {
        throw "topology가 참조하는 custom agent가 없습니다: $_"
    }
    Get-Item -LiteralPath $agentPath
})
$skillDirectories = @(Get-ChildItem -LiteralPath $skillsRoot -Directory)

if ($agentFiles.Count -eq 0) {
    throw "설치할 custom agent TOML 파일이 없습니다: $sourceAgents"
}
if ($skillDirectories.Count -eq 0) {
    throw "설치할 skill 디렉터리가 없습니다: $skillsRoot"
}

$targetAgents = Join-Path -Path $targetRoot -ChildPath ".codex\agents"
$targetSkills = Join-Path -Path $targetRoot -ChildPath ".agents\skills"
Assert-SafeTargetPath -Root $targetRoot -Path $targetAgents
Assert-SafeTargetPath -Root $targetRoot -Path $targetSkills
$installItems = @()
foreach ($agentFile in $agentFiles) {
    $installItems += [PSCustomObject]@{
        Source = $agentFile.FullName
        Destination = Join-Path -Path $targetAgents -ChildPath $agentFile.Name
        Kind = "agent"
    }
}
foreach ($skillDirectory in $skillDirectories) {
    $installItems += [PSCustomObject]@{
        Source = $skillDirectory.FullName
        Destination = Join-Path -Path $targetSkills -ChildPath $skillDirectory.Name
        Kind = "skill"
    }
}

$conflicts = @($installItems | Where-Object { Test-Path -LiteralPath $_.Destination })
if ($conflicts.Count -gt 0 -and -not $Force) {
    $paths = $conflicts.Destination -join [Environment]::NewLine
    throw "기존 프로젝트 설정을 덮어쓰지 않습니다. -Force로 백업 후 교체할 수 있습니다:`n$paths"
}

New-Item -ItemType Directory -Force -Path $targetAgents, $targetSkills | Out-Null
Assert-SafeTargetPath -Root $targetRoot -Path $targetAgents
Assert-SafeTargetPath -Root $targetRoot -Path $targetSkills

$stagedItems = [System.Collections.Generic.List[object]]::new()
$committedItems = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($item in $installItems) {
        Assert-SafeTargetPath -Root $targetRoot -Path $item.Destination
        $tempPath = New-StagedProjectItem -Source $item.Source -Destination $item.Destination -UseSymlink:$Symlink.IsPresent
        $stagedItems.Add([PSCustomObject]@{
            Source = $item.Source
            Destination = $item.Destination
            Kind = $item.Kind
            TempPath = $tempPath
        })
    }

    foreach ($item in $stagedItems) {
        Assert-SafeTargetPath -Root $targetRoot -Path $item.Destination
        Assert-SafeTargetPath -Root $targetRoot -Path (Split-Path -Parent $item.TempPath)
        $backupPath = $null
        if ($Force) {
            $backupPath = Backup-ExistingPath $item.Destination
        }
        try {
            Move-Item -LiteralPath $item.TempPath -Destination $item.Destination
        }
        catch {
            if ($null -ne $backupPath -and -not (Test-Path -LiteralPath $item.Destination) -and (Test-Path -LiteralPath $backupPath)) {
                Move-Item -LiteralPath $backupPath -Destination $item.Destination
            }
            throw
        }
        $committedItems.Add([PSCustomObject]@{
            Destination = $item.Destination
            BackupPath = $backupPath
        })

        $method = if ($Symlink) { "symlink" } else { "복사" }
        $label = if ($item.Kind -eq "agent") { "custom agent" } else { "skill" }
        Write-Host "$label $method 설치 완료: $($item.Destination)"
    }
}
catch {
    for ($index = $committedItems.Count - 1; $index -ge 0; $index--) {
        $committed = $committedItems[$index]
        Assert-SafeTargetPath -Root $targetRoot -Path (Split-Path -Parent $committed.Destination)
        if (Test-Path -LiteralPath $committed.Destination) {
            Remove-Item -LiteralPath $committed.Destination -Force -Recurse
        }
        if ($null -ne $committed.BackupPath -and (Test-Path -LiteralPath $committed.BackupPath)) {
            Move-Item -LiteralPath $committed.BackupPath -Destination $committed.Destination
        }
    }
    foreach ($item in $stagedItems) {
        Assert-SafeTargetPath -Root $targetRoot -Path (Split-Path -Parent $item.TempPath)
        if (Test-Path -LiteralPath $item.TempPath) {
            Remove-Item -LiteralPath $item.TempPath -Force -Recurse
        }
    }
    throw
}

Write-Host "OMS Codex $version 프로젝트 로컬 설치가 완료되었습니다: $targetRoot"
Write-Host "설치 topology: $Topology ($($agentFiles.Count) agents)"
Write-Host "기본 복사 설치 파일은 대상 프로젝트에서 직접 커스터마이즈할 수 있습니다."
Write-Host "시작 예시: `$orchestrate <작업>"
