param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$isWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows
)
if (-not $isWindowsPlatform) {
    Write-Host "설치기 junction 안전성 검증 생략: Windows가 아닙니다."
    exit 0
}

$rootFull = [System.IO.Path]::GetFullPath($Root)
$workspace = Join-Path -Path $rootFull -ChildPath "_workspace"
if (-not (Test-Path -LiteralPath $workspace -PathType Container)) {
    New-Item -ItemType Directory -Path $workspace | Out-Null
}
$testRoot = Join-Path -Path $workspace -ChildPath "installer-safety-$([guid]::NewGuid().ToString('N'))"
$target = Join-Path -Path $testRoot -ChildPath "target"
$external = Join-Path -Path $testRoot -ChildPath "external"
$junction = Join-Path -Path $target -ChildPath ".codex"
$harness = Join-Path -Path $testRoot -ChildPath "harness"
$harnessAlias = Join-Path -Path $testRoot -ChildPath "harness-alias"

New-Item -ItemType Directory -Path $target, $external | Out-Null
try {
    New-Item -ItemType Junction -Path $junction -Target $external | Out-Null
    $rejected = $false
    try {
        & (Join-Path $rootFull "install.ps1") -Target $target *> $null
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw "대상 하위 junction 설치가 거부되지 않았습니다."
    }
    if (@(Get-ChildItem -LiteralPath $external -Force).Count -ne 0) {
        throw "거부된 junction 대상에 파일이 생성되었습니다."
    }

    [System.IO.Directory]::Delete($junction, $false)
    $aliasRejected = $false
    try {
        & (Join-Path $rootFull "install.ps1") -Target $rootFull -Symlink *> $null
    }
    catch {
        $aliasRejected = $true
    }
    if (-not $aliasRejected) {
        throw "원본-대상 중첩 symlink 설치가 거부되지 않았습니다."
    }

    New-Item -ItemType Directory -Path (
        Join-Path $harness ".codex"
    ), (
        Join-Path $harness ".agents\skills\init-project\references"
    ) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $rootFull "install.ps1") -Destination $harness
    Copy-Item -LiteralPath (Join-Path $rootFull "VERSION") -Destination $harness
    Copy-Item -LiteralPath (Join-Path $rootFull ".codex\agents") -Destination (Join-Path $harness ".codex\agents") -Recurse
    Copy-Item -LiteralPath (
        Join-Path $rootFull ".agents\skills\init-project\references\topology-profiles.json"
    ) -Destination (
        Join-Path $harness ".agents\skills\init-project\references\topology-profiles.json"
    )
    New-Item -ItemType Junction -Path $harnessAlias -Target $harness | Out-Null
    $physicalAliasRejected = $false
    try {
        & (Join-Path $harnessAlias "install.ps1") -Target $harness -Symlink -Force *> $null
    }
    catch {
        $physicalAliasRejected = $true
    }
    if (-not $physicalAliasRejected) {
        throw "물리적으로 같은 원본-대상 junction alias 설치가 거부되지 않았습니다."
    }
    [System.IO.Directory]::Delete($harnessAlias, $false)
}
finally {
    if (Test-Path -LiteralPath $junction) {
        [System.IO.Directory]::Delete($junction, $false)
    }
    if (Test-Path -LiteralPath $harnessAlias) {
        [System.IO.Directory]::Delete($harnessAlias, $false)
    }
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $workspacePrefix = [System.IO.Path]::GetFullPath($workspace).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    if (
        [System.IO.Directory]::Exists($resolvedTestRoot) -and
        $resolvedTestRoot.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        [System.IO.Directory]::Delete($resolvedTestRoot, $true)
    }
}

Write-Host "PowerShell 설치기 경로 안전성 검증 통과"
