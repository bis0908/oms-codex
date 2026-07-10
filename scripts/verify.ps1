$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$root = Split-Path -Parent $PSScriptRoot
$errors = New-Object System.Collections.Generic.List[string]
$agentModelPolicy = @{
    "bug-fixer.toml" = "gpt-5.6-sol"
    "compound-curator.toml" = "gpt-5.6-sol"
    "compound-learner.toml" = "gpt-5.6-terra"
    "data-layer.toml" = "gpt-5.6-sol"
    "design-reviewer.toml" = "gpt-5.6-sol"
    "evaluator.toml" = "gpt-5.6-sol"
    "milestone-tracker.toml" = "gpt-5.6-luna"
    "page-builder.toml" = "gpt-5.6-sol"
    "plan-auditor.toml" = "gpt-5.6-sol"
    "qa-guard.toml" = "gpt-5.6-terra"
    "refactor-specialist.toml" = "gpt-5.6-sol"
    "security-auditor.toml" = "gpt-5.6-sol"
    "session-archivist.toml" = "gpt-5.6-luna"
    "tdd-agent.toml" = "gpt-5.6-sol"
}
$agentEffortPolicy = @{
    "bug-fixer.toml" = "high"
    "compound-curator.toml" = "high"
    "compound-learner.toml" = "medium"
    "data-layer.toml" = "high"
    "design-reviewer.toml" = "high"
    "evaluator.toml" = "xhigh"
    "milestone-tracker.toml" = "medium"
    "page-builder.toml" = "high"
    "plan-auditor.toml" = "high"
    "qa-guard.toml" = "high"
    "refactor-specialist.toml" = "high"
    "security-auditor.toml" = "xhigh"
    "session-archivist.toml" = "medium"
    "tdd-agent.toml" = "high"
}

function Add-ErrorMessage {
    param([string]$Message)

    [void]$script:errors.Add($Message)
}

function Join-RootPath {
    param([string]$RelativePath)

    return Join-Path $root $RelativePath
}

function Require-Path {
    param([string]$RelativePath)

    $path = Join-RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-ErrorMessage "필수 경로 없음: $RelativePath"
    }
}

function Get-RequiredText {
    param([string]$RelativePath)

    $path = Join-RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-ErrorMessage "파일 없음: $RelativePath"
        return $null
    }

    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8
    }
    catch {
        Add-ErrorMessage "파일 읽기 실패: $RelativePath - $($_.Exception.Message)"
        return $null
    }
}

function Require-Text {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Label
    )

    $text = Get-RequiredText $RelativePath
    if ($null -eq $text) {
        return
    }

    if ($text -notmatch $Pattern) {
        Add-ErrorMessage "$Label 텍스트 없음: $RelativePath"
    }
}

function Get-PythonCommand {
    foreach ($candidate in @("python", "python3")) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) {
            return $candidate
        }
    }

    return $null
}

@(
    "AGENTS.md",
    "README.md",
    "install.ps1",
    "install.sh",
    ".codex-plugin\plugin.json",
    ".agents\plugins\marketplace.json",
    ".agents\skills",
    ".codex\agents"
) | ForEach-Object { Require-Path $_ }

$pluginPath = Join-RootPath ".codex-plugin\plugin.json"
if (Test-Path -LiteralPath $pluginPath -PathType Leaf) {
    try {
        $plugin = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($plugin.name -ne "oms-codex") {
            Add-ErrorMessage "plugin.json name 불일치: $($plugin.name)"
        }
        if ($plugin.skills -ne "./.agents/skills/") {
            Add-ErrorMessage "plugin.json skills 불일치: $($plugin.skills)"
        }
    }
    catch {
        Add-ErrorMessage "plugin.json JSON 파싱 실패: $($_.Exception.Message)"
    }
}

$marketplacePath = Join-RootPath ".agents\plugins\marketplace.json"
if (Test-Path -LiteralPath $marketplacePath -PathType Leaf) {
    try {
        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $entry = @($marketplace.plugins) | Where-Object { $_.name -eq "oms-codex" } | Select-Object -First 1

        if (-not $entry) {
            Add-ErrorMessage "marketplace.json oms-codex entry 없음"
        }
        else {
            if ($entry.source.source -ne "local") {
                Add-ErrorMessage "marketplace.json source.source 불일치: $($entry.source.source)"
            }
            if ($entry.source.path -ne "./") {
                Add-ErrorMessage "marketplace.json source.path 불일치: $($entry.source.path)"
            }
        }
    }
    catch {
        Add-ErrorMessage "marketplace.json JSON 파싱 실패: $($_.Exception.Message)"
    }
}

$agentsPath = Join-RootPath ".codex\agents"
if (Test-Path -LiteralPath $agentsPath -PathType Container) {
    $agentFiles = @(Get-ChildItem -LiteralPath $agentsPath -Filter "*.toml" -File)
    if ($agentFiles.Count -ne $agentEffortPolicy.Count) {
        Add-ErrorMessage ".codex\agents TOML 파일 수 불일치: $($agentFiles.Count)"
    }
    foreach ($expectedFile in $agentEffortPolicy.Keys) {
        if (-not (Test-Path -LiteralPath (Join-Path $agentsPath $expectedFile) -PathType Leaf)) {
            Add-ErrorMessage "custom agent 파일 누락: $expectedFile"
        }
    }

    foreach ($file in $agentFiles) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        foreach ($field in @("name", "description", "model", "model_reasoning_effort", "developer_instructions")) {
            $matches = [regex]::Matches($text, "(?m)^$field\s*=")
            if ($matches.Count -ne 1) {
                Add-ErrorMessage "$($file.Name) 필드 개수 불일치: $field=$($matches.Count)"
            }
        }

        $expectedName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if ($text -notmatch "(?m)^name\s*=\s*`"$([regex]::Escape($expectedName))`"\s*$") {
            Add-ErrorMessage "$($file.Name) name 필드 불일치"
        }
        if ($agentModelPolicy.ContainsKey($file.Name)) {
            $expectedModel = $agentModelPolicy[$file.Name]
            if ($text -notmatch "(?m)^model\s*=\s*`"$([regex]::Escape($expectedModel))`"\s*$") {
                Add-ErrorMessage "$($file.Name) model 정책 불일치: expected $expectedModel"
            }
        }
        else {
            Add-ErrorMessage "알 수 없는 custom agent 파일: $($file.Name)"
        }
        if ($agentEffortPolicy.ContainsKey($file.Name)) {
            $expectedEffort = $agentEffortPolicy[$file.Name]
            if ($text -notmatch "(?m)^model_reasoning_effort\s*=\s*`"$expectedEffort`"\s*$") {
                Add-ErrorMessage "$($file.Name) effort 정책 불일치: expected $expectedEffort"
            }
        }
    }

    $pythonCommand = Get-PythonCommand
    if ($null -eq $pythonCommand) {
        Add-ErrorMessage "TOML 파싱용 python 또는 python3 명령을 찾지 못했습니다"
    }
    else {
        $tomlParser = "import pathlib, sys, tomllib; [tomllib.loads(pathlib.Path(arg).read_text(encoding='utf-8')) for arg in sys.argv[1:]]"
        $pythonArgs = @("-c", $tomlParser) + @($agentFiles | ForEach-Object { $_.FullName })
        $tomlOutput = & $pythonCommand @pythonArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-ErrorMessage "custom agent TOML 파싱 실패:`n$tomlOutput"
        }
    }
}

$skillsPath = Join-RootPath ".agents\skills"
if (Test-Path -LiteralPath $skillsPath -PathType Container) {
    try {
        $skillFiles = @(Get-ChildItem -LiteralPath $skillsPath -Recurse -Filter "SKILL.md" -File)
        if ($skillFiles.Count -ne 13) {
            Add-ErrorMessage "SKILL.md 파일 수 불일치: $($skillFiles.Count)"
        }
        foreach ($file in $skillFiles) {
            $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            if ($text -notmatch '(?ms)^---\s*.*?^name:\s*.+$.*?^description:\s*.+$.*?^---\s*') {
                Add-ErrorMessage "skill frontmatter 누락: $($file.FullName)"
            }
        }
    }
    catch {
        Add-ErrorMessage ".agents\skills 검사 실패: $($_.Exception.Message)"
    }
}

$contractVerifier = Join-RootPath "scripts\verify-agent-contracts.py"
if (Test-Path -LiteralPath $contractVerifier -PathType Leaf) {
    $pythonCommand = Get-PythonCommand
    if ($null -eq $pythonCommand) {
        Add-ErrorMessage "agent 계약 검증용 python 또는 python3 명령을 찾지 못했습니다"
    }
    else {
        $contractOutput = & $pythonCommand $contractVerifier $root 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-ErrorMessage "agent 의미 계약 검증 실패:`n$contractOutput"
        }
    }
}
else {
    Add-ErrorMessage "agent 계약 검증 스크립트 없음: scripts\verify-agent-contracts.py"
}

if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
    Add-ErrorMessage "rg 명령을 찾지 못했습니다"
}
else {
    $legacyPattern = 'Agent\(|Skill\(|TaskCreate|TaskList|TaskUpdate|run_in_background|CLAUDE\.md|~/.claude|\.claude/settings\.json|\.claude-plugin|gpt-5\.4|gpt-5\.4-mini|model:\s*opus|opus'
    $legacyOutput = & rg --hidden $legacyPattern $root --glob '!scripts/verify.*' --glob '!docs/superpowers/specs/**' 2>&1
    $legacyExit = $LASTEXITCODE

    if ($legacyExit -eq 0) {
        Add-ErrorMessage "legacy 토큰 잔존:`n$legacyOutput"
    }
    elseif ($legacyExit -gt 1) {
        Add-ErrorMessage "legacy scan 실패: $legacyOutput"
    }

    $forbiddenTargetPattern = '~[/\\]\.agents[/\\]skills|\$HOME[/\\]\.agents[/\\]skills|\$env:USERPROFILE.*\.agents\\skills|\.codex[/\\]config\.toml'
    $forbiddenTargetOutput = & rg $forbiddenTargetPattern (Join-RootPath "install.ps1") (Join-RootPath "install.sh") 2>&1
    $forbiddenTargetExit = $LASTEXITCODE
    if ($forbiddenTargetExit -eq 0) {
        Add-ErrorMessage "installer 금지 대상 참조 잔존:`n$forbiddenTargetOutput"
    }
    elseif ($forbiddenTargetExit -gt 1) {
        Add-ErrorMessage "installer 금지 대상 검사 실패: $forbiddenTargetOutput"
    }
}

Require-Text "README.md" 'install\.ps1 -Symlink' "README install.ps1 -Symlink"
Require-Text "README.md" 'install\.sh --symlink' "README install.sh --symlink"
Require-Text "install.ps1" 'codex plugin marketplace add' "install.ps1 marketplace"
Require-Text "install.sh" 'codex plugin marketplace add' "install.sh marketplace"

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) {
        [Console]::Error.WriteLine($errorMessage)
    }
    exit 1
}

Write-Host "검증 통과: $root"
exit 0
