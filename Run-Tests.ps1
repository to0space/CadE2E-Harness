param(
    [string]$CoreConsolePath,
    [string]$TestDrawingPath,
    [string]$ExistingPluginPath,
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

function Resolve-CoreConsolePath {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "Core Console was not found at: $RequestedPath"
        }

        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($env:MODELY_CORE_CONSOLE_PATH)) {
        return Resolve-CoreConsolePath -RequestedPath $env:MODELY_CORE_CONSOLE_PATH
    }

    $autodeskRoot = Join-Path $env:ProgramFiles "Autodesk"
    if (Test-Path -LiteralPath $autodeskRoot -PathType Container) {
        $candidate = Get-ChildItem -LiteralPath $autodeskRoot `
            -Filter "accoreconsole.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($null -ne $candidate) {
            return $candidate.FullName
        }
    }

    throw "AutoCAD Core Console was not found. Pass -CoreConsolePath or set MODELY_CORE_CONSOLE_PATH."
}

function Quote-ProcessArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$artifactRoot = Join-Path $repoRoot "Artifacts\CadE2E-Harness"
$pluginDirectory = Join-Path $repoRoot "ModelY\bin\$Configuration\net472"
$pluginPath = Join-Path $pluginDirectory "ModelY.AutoCAD.dll"
$drawingPath = if ([string]::IsNullOrWhiteSpace($TestDrawingPath)) {
    Join-Path $repoRoot "CustomData\ZhuanZhuanStandardBlock.dwg"
} else {
    (Resolve-Path -LiteralPath $TestDrawingPath).Path
}
if (-not (Test-Path -LiteralPath $drawingPath -PathType Leaf)) {
    throw "Test drawing was not found at: $drawingPath"
}
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$workingDirectory = Join-Path $artifactRoot ("Run-" + $runTimestamp)
$scriptPath = Join-Path $workingDirectory "ConfigDiscovery.scr"
$logPath = Join-Path $workingDirectory "CoreConsole.log"

New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($ExistingPluginPath)) {
    Write-Host "Building ModelY AutoCAD plugin..."
    & dotnet build (Join-Path $repoRoot "ModelY\ModelY.AutoCAD.csproj") `
        -c $Configuration `
        -warnaserror:MSB3026
    if ($LASTEXITCODE -ne 0) {
        throw "ModelY build failed with exit code $LASTEXITCODE."
    }
} else {
    $pluginPath = (Resolve-Path -LiteralPath $ExistingPluginPath).Path
    Write-Host "Testing existing ModelY deployment: $pluginPath"
}

if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    throw "Built plugin was not found at: $pluginPath"
}

$resolvedCoreConsolePath = Resolve-CoreConsolePath -RequestedPath $CoreConsolePath
$scriptLines = @(
    "_.SECURELOAD",
    "0",
    "_.NETLOAD",
    ('"' + $pluginPath + '"'),
    "T0PZ_TEST_CONFIG_DISCOVERY",
    "_.QUIT",
    "_Y"
)
[System.IO.File]::WriteAllLines(
    $scriptPath,
    $scriptLines,
    [System.Text.Encoding]::Default)

$arguments = "/i " + (Quote-ProcessArgument $drawingPath) `
    + " /s " + (Quote-ProcessArgument $scriptPath)
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $resolvedCoreConsolePath
$startInfo.Arguments = $arguments
$startInfo.WorkingDirectory = $workingDirectory
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.StandardOutputEncoding = [System.Text.Encoding]::Unicode
$startInfo.StandardErrorEncoding = [System.Text.Encoding]::Unicode
$startInfo.CreateNoWindow = $true

Write-Host "Running config discovery in AutoCAD Core Console..."
Write-Host "Drawing: $drawingPath"
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
[void]$process.Start()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    $process.Kill()
    throw "Core Console timed out after $TimeoutSeconds seconds."
}

$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
$output = $stdout + [Environment]::NewLine + $stderr
[System.IO.File]::WriteAllText($logPath, $output, [System.Text.Encoding]::UTF8)
Write-Host $output

if ($process.ExitCode -ne 0) {
    throw "Core Console exited with code $($process.ExitCode). Log: $logPath"
}

if ($output.Contains("MODELY_CONFIG_DISCOVERY_ERROR|")) {
    throw "The config discovery command reported an error. Log: $logPath"
}

if ($output.Contains("MODELY_CONFIG_LOAD_ERROR|")) {
    throw "The T0PZ YAML loader reported an error. Log: $logPath"
}

$configSourceRoots = @(
    (Join-Path $repoRoot "GenericDesignCommands"),
    (Join-Path $repoRoot "CustomDesignCommands"),
    (Join-Path $repoRoot "GlobalConfigs")
)
$sourceConfigFiles = @(
    foreach ($root in $configSourceRoots) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            Get-ChildItem -LiteralPath $root -Filter "*Config.yaml" `
                -File -Recurse |
                Where-Object {
                    $_.FullName -notmatch '[\\/](bin|obj)[\\/]'
                }
        }
    }
)
$duplicateNames = @(
    $sourceConfigFiles |
        Group-Object Name |
        Where-Object Count -gt 1
)
if ($duplicateNames.Count -gt 0) {
    $names = ($duplicateNames | ForEach-Object Name) -join ", "
    throw "Command config filenames must be globally unique: $names"
}
$requiredConfigFiles = @(
    $sourceConfigFiles |
        ForEach-Object Name |
        Sort-Object -Unique
)
if ($requiredConfigFiles.Count -eq 0) {
    throw "No command/global source configurations were found."
}
foreach ($fileName in $requiredConfigFiles) {
    $marker = "MODELY_CONFIG_FILE|$fileName|"
    if (-not $output.Contains($marker)) {
        throw "Core Console did not discover $fileName. Log: $logPath"
    }

    $loadedMarker = "MODELY_CONFIG_LOADED|$fileName"
    if (-not $output.Contains($loadedMarker)) {
        throw "T0PZ could not load $fileName. Log: $logPath"
    }
}

$expectedEndMarker = "MODELY_CONFIG_DISCOVERY_END|" + $requiredConfigFiles.Count
if (-not $output.Contains($expectedEndMarker)) {
    throw "Expected exactly $($requiredConfigFiles.Count) command/global configs. Log: $logPath"
}

Write-Host "PASS: T0PZ discovered and loaded all required configuration files in AutoCAD Core Console."
Write-Host "Plugin: $pluginPath"
Write-Host "Log: $logPath"
