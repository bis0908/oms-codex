param(
    [switch]$Symlink,
    [switch]$SkipMarketplace
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
        [string]$RelativePath
    )

    $path = Join-Path -Path $repo -ChildPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "필수 경로가 없습니다: $RelativePath"
    }

    return $path
}

function Test-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | Out-Null
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
        return
    }

    $backupPath = Get-UniquePath "$Path.bak.$(Get-KstTimestamp)"
    Move-Item -LiteralPath $Path -Destination $backupPath
    Write-Host "기존 파일을 백업했습니다: $backupPath"
    return $backupPath
}

function Install-AgentFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [switch]$UseSymlink
    )

    $tempPath = New-InstallTempPath $Destination
    $backupPath = $null

    try {
        if ($UseSymlink) {
            New-Item -ItemType SymbolicLink -Path $tempPath -Target $Source | Out-Null
        }
        else {
            Copy-Item -LiteralPath $Source -Destination $tempPath
        }

        $backupPath = Backup-ExistingPath $Destination
        Move-Item -LiteralPath $tempPath -Destination $Destination

        if ($UseSymlink) {
            Write-Host "custom agent symlink를 설치했습니다: $Destination"
        }
        else {
            Write-Host "custom agent 파일을 복사했습니다: $Destination"
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
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

if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    throw "USERPROFILE 환경 변수가 설정되어 있지 않습니다."
}

$pluginJson = Resolve-RequiredPath ".codex-plugin\plugin.json"
$marketplaceJson = Resolve-RequiredPath ".agents\plugins\marketplace.json"
$skillsRoot = Resolve-RequiredPath ".agents\skills"
$sourceAgents = Resolve-RequiredPath ".codex\agents"

Test-JsonFile $pluginJson
Test-JsonFile $marketplaceJson

if (-not $SkipMarketplace) {
    $codexCommand = Get-Command "codex" -ErrorAction SilentlyContinue
    if ($null -ne $codexCommand) {
        & codex plugin marketplace add $repo
        if ($LASTEXITCODE -ne 0) {
            throw "codex marketplace 등록 실패(exit $LASTEXITCODE): codex plugin marketplace add `"$repo`""
        }
    }
    else {
        Write-Host "codex CLI를 찾을 수 없어 marketplace 등록을 건너뜁니다."
        Write-Host "수동 실행: codex plugin marketplace add `"$repo`""
    }
}
else {
    Write-Host "marketplace 등록을 건너뛰었습니다. skill을 사용하려면 나중에 codex plugin marketplace add `"$repo`"를 실행하세요."
}

$targetAgents = Join-Path -Path $env:USERPROFILE -ChildPath ".codex\agents"
New-Item -ItemType Directory -Force -Path $targetAgents | Out-Null

$agentFiles = Get-ChildItem -LiteralPath $sourceAgents -Filter "*.toml" -File
if ($agentFiles.Count -eq 0) {
    Write-Host "설치할 custom agent TOML 파일이 없습니다: $sourceAgents"
    return
}

foreach ($agentFile in $agentFiles) {
    $targetPath = Join-Path -Path $targetAgents -ChildPath $agentFile.Name
    Install-AgentFile -Source $agentFile.FullName -Destination $targetPath -UseSymlink:$Symlink.IsPresent
}

Write-Host "OMS Codex 설치가 완료되었습니다."
Write-Host "Codex를 재시작한 뒤 Plugins 화면에서 OMS Codex를 확인하세요."
Write-Host "시작 예시: `$orchestrate <작업>"
