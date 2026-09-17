[CmdletBinding()]
param(
    [switch]$InspectOnly,
    [switch]$RepairCodexHome,
    [switch]$RepairMarketplaceSource,
    [switch]$RepairRuntimeDrift,
    [switch]$RepairAll,
    [switch]$Json,
    [switch]$SkipCliInspection,
    [string]$CodexHomePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    throw "This repair script supports Windows only."
}

if ($RepairAll) {
    $RepairCodexHome = $true
    $RepairMarketplaceSource = $true
    $RepairRuntimeDrift = $true
}

$hasRepair = $RepairCodexHome -or $RepairMarketplaceSource -or $RepairRuntimeDrift
if ($InspectOnly -and $hasRepair) {
    throw "-InspectOnly cannot be combined with repair switches."
}
if (-not $hasRepair) {
    $InspectOnly = $true
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    return [IO.Path]::GetFullPath($expanded).TrimEnd("\")
}

function Get-CanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Get-NormalizedFullPath -Path $Path
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and $null -ne $item.Target) {
            $target = @($item.Target)[0]
            if (-not [IO.Path]::IsPathRooted($target)) {
                $target = Join-Path $item.Parent.FullName $target
            }
            return (Get-NormalizedFullPath -Path $target)
        }
        return $item.FullName.TrimEnd("\")
    }
    return $full
}

function Get-ComparablePath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    $candidate = $Path.Trim()
    if ($candidate.StartsWith("\\?\")) {
        $candidate = $candidate.Substring(4)
    }
    try {
        return (Get-CanonicalPath -Path $candidate).ToLowerInvariant()
    }
    catch {
        return (Get-NormalizedFullPath -Path $candidate).ToLowerInvariant()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-PluginVersion {
    param(
        [Parameter(Mandatory = $true)][string]$BundledRoot,
        [Parameter(Mandatory = $true)][string]$PluginName
    )

    $manifest = Join-Path $BundledRoot "plugins\$PluginName\.codex-plugin\plugin.json"
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json).version
    }
    catch {
        return $null
    }
}

function Get-BundledMarketplaceConfigSource {
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return $null
    }
    $content = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    $sectionPattern = '(?ms)^\[marketplaces\.(?:"openai-bundled"|openai-bundled)\]\s*\r?\n(?<body>.*?)(?=^\[|\z)'
    $section = [regex]::Match($content, $sectionPattern)
    if (-not $section.Success) {
        return $null
    }
    $source = [regex]::Match($section.Groups["body"].Value, '(?m)^\s*source\s*=\s*["''](?<value>.*?)["'']\s*$')
    if (-not $source.Success) {
        return $null
    }
    return $source.Groups["value"].Value
}

function Set-BundledMarketplaceConfigSource {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    if ($SourcePath.Contains("'")) {
        throw "The marketplace path contains an unsupported single quote."
    }
    $literal = "source = '$SourcePath'"
    $sectionPattern = '(?ms)^\[marketplaces\.(?:"openai-bundled"|openai-bundled)\]\s*\r?\n(?<body>.*?)(?=^\[|\z)'
    $section = [regex]::Match($Content, $sectionPattern)
    if (-not $section.Success) {
        $suffix = if ($Content.EndsWith("`n")) { "" } else { "`r`n" }
        return $Content + $suffix + "`r`n[marketplaces.openai-bundled]`r`nsource_type = 'local'`r`n$literal`r`n"
    }

    $updated = $section.Value
    if ([regex]::IsMatch($updated, '(?m)^\s*source\s*=')) {
        $updated = [regex]::Replace($updated, '(?m)^\s*source\s*=.*$', $literal, 1)
    }
    else {
        $headerEnd = $updated.IndexOf("`n") + 1
        $updated = $updated.Insert($headerEnd, "$literal`r`n")
    }
    if (-not [regex]::IsMatch($updated, '(?m)^\s*source_type\s*=')) {
        $headerEnd = $updated.IndexOf("`n") + 1
        $updated = $updated.Insert($headerEnd, "source_type = 'local'`r`n")
    }
    return $Content.Substring(0, $section.Index) + $updated + $Content.Substring($section.Index + $section.Length)
}

function Set-ExistingTomlLiteral {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if ($Value.Contains("'")) {
        throw "The value for $Key contains an unsupported single quote."
    }
    $pattern = '(?m)^(?<indent>\s*)' + [regex]::Escape($Key) + '\s*=.*$'
    if (-not [regex]::IsMatch($Content, $pattern)) {
        return $Content
    }
    return [regex]::Replace(
        $Content,
        $pattern,
        { param($match) $match.Groups["indent"].Value + $Key + " = '" + $Value + "'" },
        1
    )
}

function Save-Utf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$defaultCodexHome = Join-Path $env:USERPROFILE ".codex"
$userCodexHome = [Environment]::GetEnvironmentVariable("CODEX_HOME", "User")
$selectedCodexHome = if (-not [string]::IsNullOrWhiteSpace($CodexHomePath)) {
    $CodexHomePath
}
elseif (-not [string]::IsNullOrWhiteSpace($userCodexHome)) {
    $userCodexHome
}
else {
    $defaultCodexHome
}

$lexicalCodexHome = Get-NormalizedFullPath -Path $selectedCodexHome
$canonicalCodexHome = Get-CanonicalPath -Path $lexicalCodexHome
$defaultCanonicalHome = Get-CanonicalPath -Path $defaultCodexHome
$codexHomeNeedsRepair = [string]::IsNullOrWhiteSpace($userCodexHome) -and
    ((Get-ComparablePath -Path $defaultCodexHome) -ne (Get-NormalizedFullPath -Path $defaultCodexHome).ToLowerInvariant())
if (-not [string]::IsNullOrWhiteSpace($userCodexHome)) {
    $codexHomeNeedsRepair = (Get-NormalizedFullPath -Path $userCodexHome).ToLowerInvariant() -ne $canonicalCodexHome.ToLowerInvariant()
}

$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $package) {
    throw "The OpenAI.Codex AppX package was not found."
}

$resourcesRoot = Join-Path $package.InstallLocation "app\resources"
$bundledRoot = Join-Path $resourcesRoot "plugins\openai-bundled"
$bundledManifest = Join-Path $bundledRoot ".agents\plugins\marketplace.json"
$materializedRoot = Join-Path $canonicalCodexHome ".tmp\bundled-marketplaces\openai-bundled"
$materializedManifest = Join-Path $materializedRoot ".agents\plugins\marketplace.json"
$configPath = Join-Path $canonicalCodexHome "config.toml"
$configuredMarketplaceSource = Get-BundledMarketplaceConfigSource -ConfigPath $configPath

function Get-CodexHomeAwareComparablePath {
    param([AllowNull()][string]$Path)

    $comparable = Get-ComparablePath -Path $Path
    if ($null -eq $comparable) {
        return $null
    }
    $defaultPrefix = (Get-NormalizedFullPath -Path $defaultCodexHome).ToLowerInvariant()
    $canonicalPrefix = $defaultCanonicalHome.ToLowerInvariant()
    if ($defaultPrefix -ne $canonicalPrefix -and
        ($comparable -eq $defaultPrefix -or $comparable.StartsWith($defaultPrefix + "\"))) {
        return $canonicalPrefix + $comparable.Substring($defaultPrefix.Length)
    }
    return $comparable
}

$marketplaceSourceMismatch = $null -ne $configuredMarketplaceSource -and
    (Get-CodexHomeAwareComparablePath -Path $configuredMarketplaceSource) -ne
    (Get-CodexHomeAwareComparablePath -Path $materializedRoot)

$runtimeSources = @(
    [pscustomobject]@{ Name = "codex.exe"; RelativeSource = "codex.exe" },
    [pscustomobject]@{ Name = "codex-code-mode-host.exe"; RelativeSource = "codex-code-mode-host.exe" },
    [pscustomobject]@{ Name = "node.exe"; RelativeSource = "cua_node\bin\node.exe" },
    [pscustomobject]@{ Name = "node_repl.exe"; RelativeSource = "cua_node\bin\node_repl.exe" },
    [pscustomobject]@{ Name = "codex-command-runner.exe"; RelativeSource = "codex-command-runner.exe" },
    [pscustomobject]@{ Name = "codex-windows-sandbox-setup.exe"; RelativeSource = "codex-windows-sandbox-setup.exe" }
)
$localBin = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
$runtimeRows = @()
foreach ($runtimeSource in $runtimeSources) {
    $source = Join-Path $resourcesRoot $runtimeSource.RelativeSource
    $destination = Join-Path $localBin $runtimeSource.Name
    $sourceHash = Get-FileSha256 -Path $source
    $destinationHash = Get-FileSha256 -Path $destination
    $runtimeRows += [pscustomobject]@{
        Name = $runtimeSource.Name
        SourceExists = $null -ne $sourceHash
        DestinationExists = $null -ne $destinationHash
        Matches = $null -ne $sourceHash -and $sourceHash -eq $destinationHash
        Source = $source
        Destination = $destination
        SourceHash = $sourceHash
        DestinationHash = $destinationHash
    }
}
$runtimeDrift = @($runtimeRows | Where-Object { $_.SourceExists -and -not $_.Matches }).Count -gt 0
$runtimeDriftNames = @($runtimeRows | Where-Object { $_.SourceExists -and -not $_.Matches } | ForEach-Object { $_.Name })
$configContentForInspection = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
}
else {
    ""
}
$runtimeOverrideNames = @("CODEX_CLI_PATH", "CODEX_BROWSER_USE_NODE_PATH", "CODEX_NODE_REPL_PATH")
$relocatedRuntimeConfigured = $configContentForInspection.IndexOf($localBin, [StringComparison]::OrdinalIgnoreCase) -ge 0
foreach ($name in $runtimeOverrideNames) {
    $userValue = [Environment]::GetEnvironmentVariable($name, "User")
    if (-not [string]::IsNullOrWhiteSpace($userValue) -and
        (Get-ComparablePath -Path $userValue).StartsWith((Get-ComparablePath -Path $localBin))) {
        $relocatedRuntimeConfigured = $true
    }
}
$runtimeDriftActionable = $runtimeDrift -and $relocatedRuntimeConfigured

$pluginChecks = @()
$requiredClients = @{
    browser = "scripts\browser-client.mjs"
    chrome = "scripts\browser-client.mjs"
    "computer-use" = "skills\computer-use\SKILL.md"
}
foreach ($pluginName in @("browser", "chrome", "computer-use", "sites", "visualize")) {
    $version = Get-PluginVersion -BundledRoot $bundledRoot -PluginName $pluginName
    $cacheRoot = Join-Path $canonicalCodexHome "plugins\cache\openai-bundled\$pluginName"
    $versionRoot = if ($null -ne $version) { Join-Path $cacheRoot $version } else { $null }
    $clientRelative = $requiredClients[$pluginName]
    $clientPath = if ($null -ne $clientRelative -and $null -ne $versionRoot) { Join-Path $versionRoot $clientRelative } else { $null }
    $pluginChecks += [pscustomobject]@{
        Name = $pluginName
        BundledVersion = $version
        VersionCacheExists = $null -ne $versionRoot -and (Test-Path -LiteralPath $versionRoot -PathType Container)
        RequiredClientExists = $null -eq $clientPath -or (Test-Path -LiteralPath $clientPath -PathType Leaf)
    }
}

$cliPath = Join-Path $localBin "codex.exe"
if (-not (Test-Path -LiteralPath $cliPath -PathType Leaf)) {
    $cliPath = Join-Path $resourcesRoot "codex.exe"
}
$cliMarketplaceSeen = $false
$enabledBundledPlugins = @()
$cliError = $null
if ($SkipCliInspection) {
    $cliMarketplaceSeen = $null
}
elseif (Test-Path -LiteralPath $cliPath -PathType Leaf) {
    $previousProcessCodexHome = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = $canonicalCodexHome
        $marketplaceOutput = & $cliPath plugin marketplace list 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw $marketplaceOutput.Trim()
        }
        $cliMarketplaceSeen = $marketplaceOutput -match '(?m)^openai-bundled\s'
        $pluginOutput = & $cliPath plugin list 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw $pluginOutput.Trim()
        }
        $enabledBundledPlugins = @(
            [regex]::Matches($pluginOutput, '(?m)^(?<name>[^\s]+@openai-bundled)\s+installed, enabled') |
                ForEach-Object { $_.Groups["name"].Value }
        )
    }
    catch {
        $cliError = $_.Exception.Message
    }
    finally {
        if ($null -eq $previousProcessCodexHome) {
            Remove-Item Env:\CODEX_HOME -ErrorAction SilentlyContinue
        }
        else {
            $env:CODEX_HOME = $previousProcessCodexHome
        }
    }
}
else {
    $cliError = "Codex CLI not found."
}

$actions = @()
$backupDirectory = $null
$backupTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Get-BackupDirectory {
    if ($null -eq $script:backupDirectory) {
        $script:backupDirectory = Join-Path $canonicalCodexHome "backups\bundled-plugin-repair-$backupTimestamp"
        New-Item -ItemType Directory -Path $script:backupDirectory -Force | Out-Null
    }
    return $script:backupDirectory
}

function Backup-ConfigIfPresent {
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $destination = Join-Path (Get-BackupDirectory) "config.toml"
        if (-not (Test-Path -LiteralPath $destination)) {
            Copy-Item -LiteralPath $configPath -Destination $destination
        }
    }
}

function Backup-UserEnvironment {
    $destination = Join-Path (Get-BackupDirectory) "environment-before.json"
    if (Test-Path -LiteralPath $destination) {
        return
    }
    $names = @(
        "CODEX_HOME",
        "CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE",
        "CODEX_CLI_PATH",
        "CODEX_BROWSER_USE_NODE_PATH",
        "CODEX_NODE_REPL_PATH"
    )
    $values = [ordered]@{}
    foreach ($name in $names) {
        $values[$name] = [Environment]::GetEnvironmentVariable($name, "User")
    }
    Save-Utf8Text -Path $destination -Content (($values | ConvertTo-Json -Depth 3) + "`r`n")
}

if ($RepairCodexHome) {
    Backup-UserEnvironment
    [Environment]::SetEnvironmentVariable("CODEX_HOME", $canonicalCodexHome, "User")
    $actions += "Set user CODEX_HOME to the canonical Codex data path."
}

if ($RepairMarketplaceSource) {
    if (-not (Test-Path -LiteralPath $materializedManifest -PathType Leaf)) {
        throw "Cannot repair marketplace source because the materialized marketplace manifest is missing."
    }
    Backup-ConfigIfPresent
    $configContent = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    }
    else {
        ""
    }
    $namespacedSource = "\\?\$materializedRoot"
    $updatedConfig = Set-BundledMarketplaceConfigSource -Content $configContent -SourcePath $namespacedSource
    if ($updatedConfig -ne $configContent) {
        Save-Utf8Text -Path $configPath -Content $updatedConfig
        $actions += "Updated the openai-bundled marketplace source in config.toml."
    }
    else {
        $actions += "The openai-bundled marketplace source was already correct."
    }
}

if ($RepairRuntimeDrift) {
    $runningCodex = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -in @("ChatGPT.exe", "Codex.exe", "codex.exe", "node_repl.exe", "codex-code-mode-host.exe")
            }
    )
    if ($runningCodex.Count -gt 0) {
        throw "Codex processes are still running. Fully exit Codex, then run -RepairRuntimeDrift from PowerShell."
    }

    $mismatchedRuntime = @($runtimeRows | Where-Object { $_.SourceExists -and -not $_.Matches })
    if ($mismatchedRuntime.Count -gt 0) {
        $runtimeBackup = Join-Path (Get-BackupDirectory) "runtime"
        New-Item -ItemType Directory -Path $runtimeBackup -Force | Out-Null
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null
        foreach ($row in $mismatchedRuntime) {
            if (Test-Path -LiteralPath $row.Destination -PathType Leaf) {
                Copy-Item -LiteralPath $row.Destination -Destination (Join-Path $runtimeBackup $row.Name)
            }
            Copy-Item -LiteralPath $row.Source -Destination $row.Destination -Force
            $actions += "Synchronized runtime file $($row.Name)."
        }
    }
    else {
        $actions += "Runtime files already match the current AppX package."
    }

    Backup-UserEnvironment
    $runtimeEnvironment = [ordered]@{
        CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE = "1"
        CODEX_CLI_PATH = (Join-Path $localBin "codex.exe")
        CODEX_BROWSER_USE_NODE_PATH = (Join-Path $localBin "node.exe")
        CODEX_NODE_REPL_PATH = (Join-Path $localBin "node_repl.exe")
    }
    foreach ($entry in $runtimeEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "User")
    }

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        Backup-ConfigIfPresent
        $runtimeConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        $runtimeConfig = Set-ExistingTomlLiteral -Content $runtimeConfig -Key "CODEX_CLI_PATH" -Value (Join-Path $localBin "codex.exe")
        $runtimeConfig = Set-ExistingTomlLiteral -Content $runtimeConfig -Key "NODE_REPL_NODE_PATH" -Value (Join-Path $localBin "node.exe")
        $runtimeConfig = Set-ExistingTomlLiteral -Content $runtimeConfig -Key "CODEX_BROWSER_USE_NODE_PATH" -Value (Join-Path $localBin "node.exe")
        $runtimeConfig = Set-ExistingTomlLiteral -Content $runtimeConfig -Key "CODEX_NODE_REPL_PATH" -Value (Join-Path $localBin "node_repl.exe")

        $browserVersion = Get-PluginVersion -BundledRoot $bundledRoot -PluginName "browser"
        if ($null -ne $browserVersion) {
            $runtimeConfig = Set-ExistingTomlLiteral -Content $runtimeConfig -Key "BROWSER_USE_CODEX_APP_VERSION" -Value $browserVersion
        }
        $browserClient = Join-Path $bundledRoot "plugins\browser\scripts\browser-client.mjs"
        $browserHash = Get-FileSha256 -Path $browserClient
        if ($null -ne $browserHash) {
            $runtimeConfig = Set-ExistingTomlLiteral -Content $runtimeConfig -Key "NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S" -Value $browserHash
        }
        Save-Utf8Text -Path $configPath -Content $runtimeConfig
        $actions += "Updated existing runtime and Browser trust entries in config.toml."
    }
}

if ($RepairRuntimeDrift) {
    foreach ($row in $runtimeRows) {
        $row.DestinationHash = Get-FileSha256 -Path $row.Destination
        $row.DestinationExists = $null -ne $row.DestinationHash
        $row.Matches = $row.SourceExists -and $row.SourceHash -eq $row.DestinationHash
    }
    $runtimeDriftNames = @($runtimeRows | Where-Object { $_.SourceExists -and -not $_.Matches } | ForEach-Object { $_.Name })
    $runtimeDrift = $runtimeDriftNames.Count -gt 0
    $runtimeDriftActionable = $runtimeDrift -and $relocatedRuntimeConfigured
}

$recommendations = @()
if ($codexHomeNeedsRepair) {
    $recommendations += "Persist the canonical Codex data path with -RepairCodexHome."
}
if ($marketplaceSourceMismatch) {
    $recommendations += "Repair the stale openai-bundled source with -RepairMarketplaceSource."
}
if ($runtimeDriftActionable) {
    $recommendations += "Fully exit Codex and run -RepairRuntimeDrift."
}
if (-not $SkipCliInspection -and -not $cliMarketplaceSeen) {
    $recommendations += "The Codex CLI does not currently list openai-bundled under the canonical home."
}
if ($recommendations.Count -eq 0) {
    $recommendations += "No path, marketplace, or runtime drift was detected. Verify capabilities in a fresh Codex task."
}

$report = [ordered]@{
    SchemaVersion = 1
    Mode = if ($InspectOnly) { "inspect" } else { "repair" }
    Package = [ordered]@{
        Name = $package.Name
        Version = $package.Version.ToString()
        InstallLocation = $package.InstallLocation
        BundledManifestExists = Test-Path -LiteralPath $bundledManifest -PathType Leaf
    }
    CodexHome = [ordered]@{
        Default = $defaultCodexHome
        DefaultCanonical = $defaultCanonicalHome
        UserEnvironment = $userCodexHome
        Lexical = $lexicalCodexHome
        Canonical = $canonicalCodexHome
        NeedsRepair = $codexHomeNeedsRepair
    }
    Marketplace = [ordered]@{
        CliInspectionSkipped = [bool]$SkipCliInspection
        ConfiguredSource = $configuredMarketplaceSource
        ExpectedMaterializedSource = $materializedRoot
        MaterializedManifestExists = Test-Path -LiteralPath $materializedManifest -PathType Leaf
        SourceMismatch = $marketplaceSourceMismatch
        CliListsBundledMarketplace = $cliMarketplaceSeen
        EnabledBundledPlugins = $enabledBundledPlugins
        CliError = $cliError
    }
    Plugins = $pluginChecks
    Runtime = [ordered]@{
        DriftDetected = $runtimeDrift
        RelocatedRuntimeConfigured = $relocatedRuntimeConfigured
        RepairRecommended = $runtimeDriftActionable
        Files = $runtimeRows
    }
    Actions = $actions
    BackupDirectory = $backupDirectory
    RestartRequired = $hasRepair
    Recommendations = $recommendations
}

if ($Json) {
    $report | ConvertTo-Json -Depth 8
    return
}

Write-Output "Codex Windows bundled plugin health"
Write-Output "  Package version:       $($report.Package.Version)"
Write-Output "  Lexical CODEX_HOME:    $lexicalCodexHome"
Write-Output "  Canonical CODEX_HOME:  $canonicalCodexHome"
Write-Output "  CODEX_HOME repair:     $codexHomeNeedsRepair"
Write-Output "  Marketplace mismatch:  $marketplaceSourceMismatch"
Write-Output "  Marketplace visible:   $cliMarketplaceSeen"
Write-Output "  Runtime drift:         $runtimeDrift"
Write-Output "  Runtime repair needed: $runtimeDriftActionable"
if ($runtimeDriftNames.Count -gt 0) {
    Write-Output "  Runtime drift files:   $($runtimeDriftNames -join ', ')"
}
Write-Output "  Enabled bundled:       $($enabledBundledPlugins -join ', ')"
if ($null -ne $cliError) {
    Write-Output "  CLI inspection error:  $cliError"
}
Write-Output ""
Write-Output "Recommendations:"
foreach ($recommendation in $recommendations) {
    Write-Output "  - $recommendation"
}
if ($actions.Count -gt 0) {
    Write-Output ""
    Write-Output "Actions completed:"
    foreach ($action in $actions) {
        Write-Output "  - $action"
    }
    if ($null -ne $backupDirectory) {
        Write-Output "  - Backup: $backupDirectory"
    }
    Write-Output "  - Fully exit and reopen Codex Desktop before verification."
}
