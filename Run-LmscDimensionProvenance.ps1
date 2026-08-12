param(
    [Parameter(Mandatory = $true)]
    [string]$TestDrawingPath,
    [string]$CoreConsolePath,
    [double]$TargetMeasurement = 970.0,
    [double]$MeasurementTolerance = 1.0,
    [switch]$UseExistingBuild,
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",
    [int]$TimeoutSeconds = 300
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
            -Filter "accoreconsole.exe" -File -Recurse `
            -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($null -ne $candidate) {
            return $candidate.FullName
        }
    }

    throw "AutoCAD Core Console was not found. Pass -CoreConsolePath."
}

function Quote-ProcessArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$sourceDrawingPath = (Resolve-Path -LiteralPath $TestDrawingPath).Path
if (-not (Test-Path -LiteralPath $sourceDrawingPath -PathType Leaf)) {
    throw "Test drawing was not found at: $sourceDrawingPath"
}

$facadePath = Join-Path $repoRoot "ModelY\bin\$Configuration\net472\ModelY.AutoCAD.dll"
$lmscAssemblyPath = Join-Path $repoRoot "ModelY\bin\$Configuration\net472\ModelY.CustomDesignCommands.ZhuanZhuanLmsc.dll"
$testAssemblyPath = Join-Path $repoRoot "Tests\ModelY.AutoCAD.Tests\bin\$Configuration\net472\ModelY.AutoCAD.Tests.dll"
$artifactRoot = Join-Path $repoRoot "Artifacts\CadE2E-Harness"
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$reportDirectory = Join-Path $artifactRoot ("Lmsc-970-Provenance-" + $runTimestamp)
$workingDrawingPath = Join-Path $reportDirectory "source-copy.dwg"
$scriptPath = Join-Path $reportDirectory "RunLmscDimensionProvenance.scr"
$logPath = Join-Path $reportDirectory "CoreConsole.log"
$reportPath = Join-Path $reportDirectory "report.html"
$csvPath = Join-Path $reportDirectory "evidence.csv"
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourceDrawingPath -Destination $workingDrawingPath

if (-not $UseExistingBuild) {
    Write-Host "Building the standard ModelY facade deployment..."
    & dotnet build (Join-Path $repoRoot "ModelY\ModelY.AutoCAD.csproj") `
        -c $Configuration `
        -warnaserror:MSB3026
    if ($LASTEXITCODE -ne 0) {
        throw "ModelY facade build failed with exit code $LASTEXITCODE. Close AutoCAD and retry if the deployment is locked."
    }

    Write-Host "Building the ModelY AutoCAD diagnostic command..."
    & dotnet build (Join-Path $repoRoot "Tests\ModelY.AutoCAD.Tests\ModelY.AutoCAD.Tests.csproj") `
        -c $Configuration `
        -warnaserror:MSB3026
    if ($LASTEXITCODE -ne 0) {
        throw "ModelY AutoCAD test build failed with exit code $LASTEXITCODE."
    }
} else {
    Write-Host "Using the existing standard ModelY deployment and diagnostic build."
}

foreach ($requiredPath in @($facadePath, $lmscAssemblyPath, $testAssemblyPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required test assembly was not found at: $requiredPath"
    }
}

$scriptLines = @(
    "_.SECURELOAD",
    "0",
    "_.FILEDIA",
    "0",
    "_.NETLOAD",
    ('"' + $facadePath + '"'),
    "_.NETLOAD",
    ('"' + $lmscAssemblyPath + '"'),
    "_.NETLOAD",
    ('"' + $testAssemblyPath + '"'),
    "T0_LMSC_DIMENSION_PROVENANCE",
    "_.QUIT",
    "_Y"
)
[System.IO.File]::WriteAllLines(
    $scriptPath,
    $scriptLines,
    [System.Text.Encoding]::Default)

$resolvedCoreConsolePath = Resolve-CoreConsolePath -RequestedPath $CoreConsolePath
$arguments = "/i " + (Quote-ProcessArgument $workingDrawingPath) `
    + " /s " + (Quote-ProcessArgument $scriptPath)
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $resolvedCoreConsolePath
$startInfo.Arguments = $arguments
$startInfo.WorkingDirectory = $reportDirectory
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.StandardOutputEncoding = [System.Text.Encoding]::Unicode
$startInfo.StandardErrorEncoding = [System.Text.Encoding]::Unicode
$startInfo.CreateNoWindow = $true
$startInfo.EnvironmentVariables["MODELY_LMSC_DIMENSION_REPORT_DIR"] = $reportDirectory
$startInfo.EnvironmentVariables["MODELY_LMSC_DIMENSION_TARGET"] = `
    $TargetMeasurement.ToString([System.Globalization.CultureInfo]::InvariantCulture)
$startInfo.EnvironmentVariables["MODELY_LMSC_DIMENSION_TOLERANCE"] = `
    $MeasurementTolerance.ToString([System.Globalization.CultureInfo]::InvariantCulture)

Write-Host "Running the read-only LMSC dimension provenance test in AutoCAD Core Console..."
Write-Host "Source drawing: $sourceDrawingPath"
Write-Host "Working copy: $workingDrawingPath"
Write-Host "Target: $TargetMeasurement +/- $MeasurementTolerance"
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
if ($output.Contains("MODELY_LMSC_DIMENSION_PROVENANCE_END|FAIL")) {
    throw "The LMSC dimension provenance command reported a failure. Log: $logPath"
}
if (-not $output.Contains("MODELY_LMSC_DIMENSION_PROVENANCE_END|PASS")) {
    throw "The LMSC dimension provenance command did not produce its PASS marker. Log: $logPath"
}
foreach ($requiredArtifact in @($reportPath, $csvPath, $workingDrawingPath)) {
    if (-not (Test-Path -LiteralPath $requiredArtifact -PathType Leaf)) {
        throw "Required diagnostic artifact was not created: $requiredArtifact"
    }
}

Write-Host "PASS: LMSC dimension provenance report created."
Write-Host "Facade: $facadePath"
Write-Host "Test assembly: $testAssemblyPath"
Write-Host "Report: $reportPath"
Write-Host "Evidence: $csvPath"
Write-Host "Log: $logPath"
