param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Target,

    [switch]$Symlink,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

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

function Install-ProjectItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $true)]
        [ValidateSet("agent", "skill")]
        [string]$Kind,

        [switch]$UseSymlink,
        [switch]$ReplaceExisting
    )

    $tempPath = New-InstallTempPath $Destination
    $backupPath = $null

    try {
        if ($UseSymlink) {
            New-Item -ItemType SymbolicLink -Path $tempPath -Target $Source | Out-Null
        }
        else {
            Copy-Item -LiteralPath $Source -Destination $tempPath -Recurse
        }

        if ($ReplaceExisting) {
            $backupPath = Backup-ExistingPath $Destination
        }
        Move-Item -LiteralPath $tempPath -Destination $Destination

        $method = if ($UseSymlink) { "symlink" } else { "복사" }
        $label = if ($Kind -eq "agent") { "custom agent" } else { "skill" }
        Write-Host "$label $method 설치 완료: $Destination"
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -Recurse
        }
        if ($null -ne $backupPath -and -not (Test-Path -LiteralPath $Destination) -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $Destination
        }
        throw
    }
}

$repo = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($repo)) {
    $repo = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$targetRoot = [System.IO.Path]::GetFullPath($Target)
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "대상 프로젝트 디렉터리가 없습니다: $targetRoot"
}

$skillsRoot = Resolve-RequiredPath -BasePath $repo -RelativePath ".agents\skills"
$sourceAgents = Resolve-RequiredPath -BasePath $repo -RelativePath ".codex\agents"
$versionPath = Resolve-RequiredPath -BasePath $repo -RelativePath "VERSION"
$version = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION 형식이 올바르지 않습니다: $version"
}
$agentFiles = @(Get-ChildItem -LiteralPath $sourceAgents -Filter "*.toml" -File)
$skillDirectories = @(Get-ChildItem -LiteralPath $skillsRoot -Directory)

if ($agentFiles.Count -eq 0) {
    throw "설치할 custom agent TOML 파일이 없습니다: $sourceAgents"
}
if ($skillDirectories.Count -eq 0) {
    throw "설치할 skill 디렉터리가 없습니다: $skillsRoot"
}

$targetAgents = Join-Path -Path $targetRoot -ChildPath ".codex\agents"
$targetSkills = Join-Path -Path $targetRoot -ChildPath ".agents\skills"
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
foreach ($item in $installItems) {
    Install-ProjectItem -Source $item.Source -Destination $item.Destination -Kind $item.Kind -UseSymlink:$Symlink.IsPresent -ReplaceExisting:$Force.IsPresent
}

Write-Host "OMS Codex $version 프로젝트 로컬 설치가 완료되었습니다: $targetRoot"
Write-Host "기본 복사 설치 파일은 대상 프로젝트에서 직접 커스터마이즈할 수 있습니다."
Write-Host "시작 예시: `$orchestrate <작업>"
