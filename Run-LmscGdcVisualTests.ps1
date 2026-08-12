param(
    [Parameter(Mandatory = $true)]
    [string]$TestDrawingPath,
    [string]$CoreConsolePath,
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",
    [int]$TimeoutSeconds = 600
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
$sourceDrawingPath = (Resolve-Path -LiteralPath $TestDrawingPath).Path
$gdcProjectPath = Join-Path $repoRoot "GenericDesignCommands\Lmsc\ModelY.GenericDesignCommands.Lmsc.csproj"
$gdcAssemblyPath = Join-Path $repoRoot "GenericDesignCommands\Lmsc\bin\$Configuration\net472\ModelY.GenericDesignCommands.Lmsc.dll"
$cdcAssemblyPath = Join-Path $repoRoot "CustomDesignCommands\ZhuanZhuanLmsc\bin\$Configuration\net472\ModelY.CustomDesignCommands.ZhuanZhuanLmsc.dll"
$testProjectPath = Join-Path $repoRoot "Tests\ModelY.AutoCAD.Tests\ModelY.AutoCAD.Tests.csproj"
$testAssemblyPath = Join-Path $repoRoot "Tests\ModelY.AutoCAD.Tests\bin\$Configuration\net472\ModelY.AutoCAD.Tests.dll"
$artifactRoot = Join-Path $repoRoot "Artifacts\CadE2E-Harness"
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$reportDirectory = Join-Path $artifactRoot ("Lmsc-Gdc-Visual-" + $runTimestamp)
$generatedDrawingPath = Join-Path $reportDirectory "generated.dwg"
$scriptPath = Join-Path $reportDirectory "RunLmscGdcVisualTests.scr"
$logPath = Join-Path $reportDirectory "CoreConsole.log"
$reportPath = Join-Path $reportDirectory "report.html"
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null

Write-Host "Building the standard generic LMSC command output..."
& dotnet build $gdcProjectPath -c $Configuration -warnaserror:MSB3026
if ($LASTEXITCODE -ne 0) {
    throw "Generic LMSC build failed with exit code $LASTEXITCODE."
}

Write-Host "Building the ModelY GDC visual test command..."
& dotnet build $testProjectPath -c $Configuration -warnaserror:MSB3026
if ($LASTEXITCODE -ne 0) {
    throw "ModelY AutoCAD test build failed with exit code $LASTEXITCODE."
}

foreach ($requiredPath in @(
    $gdcAssemblyPath,
    $cdcAssemblyPath,
    $testAssemblyPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required test assembly was not found at: $requiredPath"
    }
}

Copy-Item -LiteralPath $sourceDrawingPath -Destination $generatedDrawingPath

$scriptLines = @(
    "_.SECURELOAD",
    "0",
    "_.BACKGROUNDPLOT",
    "0",
    "_.FILEDIA",
    "0",
    "_.NETLOAD",
    ('"' + $gdcAssemblyPath + '"'),
    "_.NETLOAD",
    ('"' + $cdcAssemblyPath + '"'),
    "_.NETLOAD",
    ('"' + $testAssemblyPath + '"'),
    "RunGdcLmscVisualTests",
    "_.QUIT",
    "_Y"
)
[System.IO.File]::WriteAllLines(
    $scriptPath,
    $scriptLines,
    [System.Text.Encoding]::Default)

$resolvedCoreConsolePath = Resolve-CoreConsolePath -RequestedPath $CoreConsolePath
$arguments = "/i " + (Quote-ProcessArgument $generatedDrawingPath) `
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
$startInfo.EnvironmentVariables["MODELY_GDC_LMSC_VISUAL_REPORT_DIR"] = $reportDirectory

Write-Host "Running the configured generic LMSC in AutoCAD Core Console..."
Write-Host "Source drawing: $sourceDrawingPath"
Write-Host "Generated copy: $generatedDrawingPath"
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
[void]$process.Start()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    $process.Kill()
    throw "Core Console timed out after $TimeoutSeconds seconds."
}

$output = $stdoutTask.Result + [Environment]::NewLine + $stderrTask.Result
[System.IO.File]::WriteAllText(
    $logPath,
    $output,
    [System.Text.Encoding]::UTF8)
Write-Host $output

if ($process.ExitCode -ne 0) {
    throw "Core Console exited with code $($process.ExitCode). Log: $logPath"
}
if ($output.Contains("MODELY_GDC_LMSC_VISUAL_TEST_END|FAIL")) {
    throw "RunGdcLmscVisualTests reported a failure. Log: $logPath"
}
if (-not $output.Contains("MODELY_GDC_LMSC_VISUAL_TEST_END|PASS")) {
    throw "The configured GDC test did not produce its PASS marker. Log: $logPath"
}

foreach ($requiredArtifact in @(
    $reportPath,
    $generatedDrawingPath,
    (Join-Path $reportDirectory "inferred-LmscConfig.yaml"),
    (Join-Path $reportDirectory "facade-A.pdf"),
    (Join-Path $reportDirectory "facade-A.png"),
    (Join-Path $reportDirectory "facade-B.pdf"),
    (Join-Path $reportDirectory "facade-B.png"),
    (Join-Path $reportDirectory "facade-C.pdf"),
    (Join-Path $reportDirectory "facade-C.png"),
    (Join-Path $reportDirectory "facade-D.pdf"),
    (Join-Path $reportDirectory "facade-D.png"))) {
    if (-not (Test-Path -LiteralPath $requiredArtifact -PathType Leaf)) {
        throw "GDC visual artifact was not created: $requiredArtifact"
    }
}

Write-Host "PASS: configured generic LMSC rendered A/B/C/D and produced an HTML report."
Write-Host "GDC: $gdcAssemblyPath"
Write-Host "Report: $reportPath"
Write-Host "Inferred config: $(Join-Path $reportDirectory 'inferred-LmscConfig.yaml')"
Write-Host "Generated DWG: $generatedDrawingPath"
Write-Host "Log: $logPath"
