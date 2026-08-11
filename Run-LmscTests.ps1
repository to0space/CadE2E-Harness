param(
    [Parameter(Mandatory = $true)]
    [string]$TestDrawingPath,
    [string]$CoreConsolePath,
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",
    [int]$TimeoutSeconds = 180
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
$drawingPath = (Resolve-Path -LiteralPath $TestDrawingPath).Path
if (-not (Test-Path -LiteralPath $drawingPath -PathType Leaf)) {
    throw "Test drawing was not found at: $drawingPath"
}

$facadePath = Join-Path $repoRoot "ModelY\bin\$Configuration\net472\ModelY.AutoCAD.dll"
$lmscAssemblyPath = Join-Path $repoRoot "ModelY\bin\$Configuration\net472\ModelY.CustomDesignCommands.ZhuanZhuanLmsc.dll"
$testAssemblyPath = Join-Path $repoRoot "Tests\ModelY.AutoCAD.Tests\bin\$Configuration\net472\ModelY.AutoCAD.Tests.dll"
$artifactRoot = Join-Path $repoRoot "Artifacts\CadE2E-Harness"
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$workingDirectory = Join-Path $artifactRoot ("Lmsc-Run-" + $runTimestamp)
$scriptPath = Join-Path $workingDirectory "RunLmscTests.scr"
$logPath = Join-Path $workingDirectory "CoreConsole.log"
New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null

Write-Host "Building the standard ModelY facade deployment..."
& dotnet build (Join-Path $repoRoot "ModelY\ModelY.AutoCAD.csproj") `
    -c $Configuration `
    -warnaserror:MSB3026
if ($LASTEXITCODE -ne 0) {
    throw "ModelY facade build failed with exit code $LASTEXITCODE. Close AutoCAD and retry if the deployment is locked."
}

Write-Host "Building RunCADtests..."
& dotnet build (Join-Path $repoRoot "Tests\ModelY.AutoCAD.Tests\ModelY.AutoCAD.Tests.csproj") `
    -c $Configuration `
    -warnaserror:MSB3026
if ($LASTEXITCODE -ne 0) {
    throw "ModelY AutoCAD test build failed with exit code $LASTEXITCODE."
}

foreach ($requiredPath in @($facadePath, $lmscAssemblyPath, $testAssemblyPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required test assembly was not found at: $requiredPath"
    }
}

$scriptLines = @(
    "_.SECURELOAD",
    "0",
    "_.NETLOAD",
    ('"' + $facadePath + '"'),
    "_.NETLOAD",
    ('"' + $lmscAssemblyPath + '"'),
    "_.NETLOAD",
    ('"' + $testAssemblyPath + '"'),
    "RunCADtests",
    "_.QUIT",
    "_Y"
)
[System.IO.File]::WriteAllLines(
    $scriptPath,
    $scriptLines,
    [System.Text.Encoding]::Default)

$resolvedCoreConsolePath = Resolve-CoreConsolePath -RequestedPath $CoreConsolePath
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
$startInfo.EnvironmentVariables["MODELY_TEST_DWG"] = $drawingPath
$startInfo.EnvironmentVariables["MODELY_LMSC_ASSEMBLY_PATH"] = $lmscAssemblyPath

Write-Host "Running LMSC tests in AutoCAD Core Console..."
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

if ($output.Contains("MODELY_CAD_TESTS_END|FAIL")) {
    throw "RunCADtests reported an LMSC test failure. Log: $logPath"
}

if (-not $output.Contains("MODELY_CAD_TESTS_END|PASS")) {
    throw "RunCADtests did not produce a completion marker. Log: $logPath"
}

Write-Host "PASS: RunCADtests completed the named-DWG LMSC readiness suite."
Write-Host "Facade: $facadePath"
Write-Host "Tests: $testAssemblyPath"
Write-Host "Log: $logPath"
