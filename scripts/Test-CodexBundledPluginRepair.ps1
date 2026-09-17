[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Repair-CodexBundledPlugins.ps1"
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Repair script is missing."
}

$userCodexHome = [Environment]::GetEnvironmentVariable("CODEX_HOME", "User")
$testCodexHome = if ([string]::IsNullOrWhiteSpace($userCodexHome)) {
    Join-Path $env:USERPROFILE ".codex"
}
else {
    $userCodexHome
}
$watchedFiles = @("config.toml") |
    ForEach-Object { Join-Path $testCodexHome $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
$hashesBefore = @{}
foreach ($path in $watchedFiles) {
    $hashesBefore[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
$userEnvironmentBefore = [ordered]@{}
foreach ($name in @("CODEX_HOME", "CODEX_CLI_PATH", "CODEX_BROWSER_USE_NODE_PATH", "CODEX_NODE_REPL_PATH")) {
    $userEnvironmentBefore[$name] = [Environment]::GetEnvironmentVariable($name, "User")
}

$json = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -InspectOnly -Json
if ($LASTEXITCODE -ne 0) {
    throw "Inspect-only execution failed."
}

$report = $json | Out-String | ConvertFrom-Json
if ($report.SchemaVersion -ne 1) {
    throw "Unexpected report schema version."
}
if ($report.Mode -ne "inspect") {
    throw "The test expected inspect mode."
}
if ([string]::IsNullOrWhiteSpace($report.CodexHome.Canonical)) {
    throw "Canonical CODEX_HOME was not reported."
}
if ($null -eq $report.Runtime.Files -or $report.Runtime.Files.Count -lt 1) {
    throw "Runtime file checks were not reported."
}
$runtimeFileNames = @($report.Runtime.Files | ForEach-Object { $_.Name })
foreach ($requiredRuntimeFile in @("codex.exe", "codex-code-mode-host.exe", "node_repl.exe", "codex-command-runner.exe")) {
    if ($requiredRuntimeFile -notin $runtimeFileNames) {
        throw "Required runtime file check is missing: $requiredRuntimeFile"
    }
}
if ($null -eq $report.Recommendations -or $report.Recommendations.Count -lt 1) {
    throw "Recommendations were not reported."
}
foreach ($path in $watchedFiles) {
    $hashAfter = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hashesBefore[$path] -ne $hashAfter) {
        throw "Inspect-only mode modified config.toml."
    }
}
$staticJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -InspectOnly -SkipCliInspection -Json
if ($LASTEXITCODE -ne 0) { throw 'Pre-start static inspection failed.' }
$staticReport = $staticJson | Out-String | ConvertFrom-Json
if (-not $staticReport.Marketplace.CliInspectionSkipped -or $null -ne $staticReport.Marketplace.CliListsBundledMarketplace) {
    throw 'Skipped CLI inspection was incorrectly represented as verified or failed.'
}
if ($staticReport.Runtime.Files.Count -ne $report.Runtime.Files.Count) { throw 'Static mode omitted runtime checks.' }
foreach ($path in $watchedFiles) {
    if ($hashesBefore[$path] -ne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) { throw 'Static inspection modified config.toml.' }
}
foreach ($name in $userEnvironmentBefore.Keys) {
    $valueAfter = [Environment]::GetEnvironmentVariable($name, "User")
    if ($userEnvironmentBefore[$name] -ne $valueAfter) {
        throw "Inspect-only mode modified a user environment variable."
    }
}

Write-Output "PASS: inspect-only mode returned a valid health report without modifying config.toml or user environment variables."
