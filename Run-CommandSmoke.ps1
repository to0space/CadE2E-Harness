param(
    [Parameter(Mandatory = $true)]
    [string[]]$BuildProjectPaths,
    [Parameter(Mandatory = $true)]
    [string[]]$AssemblyPaths,
    [Parameter(Mandatory = $true)]
    [string]$CommandName,
    [Parameter(Mandatory = $true)]
    [string]$SuccessMarker,
    [Parameter(Mandatory = $true)]
    [string]$TestDrawingPath,
    [string]$RepositoryRoot,
    [string]$ArtifactRoot,
    [string]$ProcessExitPath,
    [string]$CoreConsolePath,
    [string]$ArtifactPrefix = "Command-Smoke",
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 writes redirected host output with the active OEM/ANSI
# code page unless the console encoding is set explicitly. ModelY CLI reads the
# runner stream as UTF-8, so keep the live terminal stream aligned with the
# UTF-8 CoreConsole.log written below.
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

function Resolve-CoreConsolePath {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "Core Console was not found at: $RequestedPath"
        }

        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $configuredPath = [Environment]::GetEnvironmentVariable(
        "CAD_E2E_CORE_CONSOLE_PATH")
    if ([string]::IsNullOrWhiteSpace($configuredPath)) {
        # Compatibility with consumers created before the harness became
        # product-agnostic.
        $configuredPath = [Environment]::GetEnvironmentVariable(
            "MODELY_CORE_CONSOLE_PATH")
    }
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        return Resolve-CoreConsolePath -RequestedPath $configuredPath
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

function Resolve-RepositoryPath {
    param(
        [string]$RepositoryRoot,
        [string]$RequestedPath
    )

    if ([System.IO.Path]::IsPathRooted($RequestedPath)) {
        return [System.IO.Path]::GetFullPath($RequestedPath)
    }

    return [System.IO.Path]::GetFullPath(
        (Join-Path $RepositoryRoot $RequestedPath))
}

function Quote-ProcessArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Format-ExitCodeHex {
    param([int]$ExitCode)

    $bytes = [System.BitConverter]::GetBytes($ExitCode)
    $unsigned = [System.BitConverter]::ToUInt32($bytes, 0)
    return "0x{0:X8}" -f $unsigned
}

function Write-ProcessExitRecord {
    param(
        [string]$Path,
        [System.Collections.IDictionary]$Record
    )

    $directory = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporaryPath = $Path + "." + [Guid]::NewGuid().ToString("N") + ".tmp"
    $json = $Record | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($temporaryPath, $json, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

if ([string]::IsNullOrWhiteSpace($CommandName)) {
    throw "CommandName is required."
}
if ([string]::IsNullOrWhiteSpace($SuccessMarker)) {
    throw "SuccessMarker is required."
}
if ($BuildProjectPaths.Count -eq 0) {
    throw "At least one build project is required."
}
if ($AssemblyPaths.Count -eq 0) {
    throw "At least one assembly is required."
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} elseif ([System.IO.Path]::IsPathRooted($RepositoryRoot)) {
    $repoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
} else {
    $repoRoot = [System.IO.Path]::GetFullPath(
        (Join-Path (Get-Location).Path $RepositoryRoot))
}
if (-not (Test-Path -LiteralPath $repoRoot -PathType Container)) {
    throw "Consuming repository root was not found: $repoRoot"
}
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
    $resolvedArtifactRoot = Join-Path `
        $repoRoot `
        "Tests\Artifacts\CadE2E-Harness"
} else {
    $resolvedArtifactRoot = Resolve-RepositoryPath `
        -RepositoryRoot $repoRoot `
        -RequestedPath $ArtifactRoot
}
$sourceDrawingPath = Resolve-RepositoryPath -RepositoryRoot $repoRoot `
    -RequestedPath $TestDrawingPath
if (-not (Test-Path -LiteralPath $sourceDrawingPath -PathType Leaf)) {
    throw "Test drawing was not found at: $sourceDrawingPath"
}

$safePrefix = [regex]::Replace($ArtifactPrefix, '[^A-Za-z0-9._-]', '-')
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$workingDirectory = Join-Path `
    $resolvedArtifactRoot `
    ($safePrefix + "-" + $runTimestamp)
$workingDrawingPath = Join-Path $workingDirectory "smoke-test.dwg"
$scriptPath = Join-Path $workingDirectory "RunCommandSmoke.scr"
$logPath = Join-Path $workingDirectory "CoreConsole.log"
$resolvedProcessExitPath = if (
    [string]::IsNullOrWhiteSpace($ProcessExitPath)) {
    Join-Path $workingDirectory "process-exit.json"
} else {
    Resolve-RepositoryPath `
        -RepositoryRoot $repoRoot `
        -RequestedPath $ProcessExitPath
}
New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null
$exitRecord = [ordered]@{
    schemaVersion = 1
    state = "Starting"
    commandName = $CommandName
    processPath = $null
    processId = $null
    processStartedAtUtc = $null
    finishedAtUtc = $null
    durationMilliseconds = $null
    exitCode = $null
    exitCodeHex = $null
    timedOut = $false
    killedByHarness = $false
    successMarkerObserved = $false
    workingDirectory = $workingDirectory
    logPath = $logPath
    error = $null
}
Write-ProcessExitRecord -Path $resolvedProcessExitPath -Record $exitRecord

$process = $null
$stopwatch = $null
try {
    Copy-Item -LiteralPath $sourceDrawingPath -Destination $workingDrawingPath

    foreach ($projectPath in $BuildProjectPaths) {
        $resolvedProjectPath = Resolve-RepositoryPath `
            -RepositoryRoot $repoRoot `
            -RequestedPath $projectPath
        if (-not (Test-Path -LiteralPath $resolvedProjectPath -PathType Leaf)) {
            throw "Build project was not found at: $resolvedProjectPath"
        }

        Write-Host "Building standard project output: $resolvedProjectPath"
        & dotnet build $resolvedProjectPath `
            -c $Configuration `
            -warnaserror:MSB3026
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed with exit code ${LASTEXITCODE}: $resolvedProjectPath"
        }
    }

    $resolvedAssemblyPaths = @()
    foreach ($assemblyPath in $AssemblyPaths) {
        $resolvedAssemblyPath = Resolve-RepositoryPath `
            -RepositoryRoot $repoRoot `
            -RequestedPath $assemblyPath
        if (-not (Test-Path -LiteralPath $resolvedAssemblyPath -PathType Leaf)) {
            throw "Required assembly was not found at: $resolvedAssemblyPath"
        }

        $resolvedAssemblyPaths += $resolvedAssemblyPath
    }

    $scriptLines = @(
        "_.FILEDIA",
        "0",
        "_.CMDDIA",
        "0",
        "_.SECURELOAD",
        "0"
    )
    foreach ($assemblyPath in $resolvedAssemblyPaths) {
        $scriptLines += "_.NETLOAD"
        $scriptLines += ('"' + $assemblyPath + '"')
    }
    $scriptLines += $CommandName
    $scriptLines += "_.QSAVE"
    $scriptLines += "_.QUIT"
    $scriptLines += "_Y"
    [System.IO.File]::WriteAllLines(
        $scriptPath,
        $scriptLines,
        [System.Text.Encoding]::Default)

    $resolvedCoreConsolePath = Resolve-CoreConsolePath `
        -RequestedPath $CoreConsolePath
    $arguments = "/i " + (Quote-ProcessArgument $workingDrawingPath) `
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

    Write-Host "Running command smoke test in AutoCAD Core Console..."
    Write-Host "Command: $CommandName"
    Write-Host "Drawing copy: $workingDrawingPath"
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $exitRecord.processPath = $resolvedCoreConsolePath
    $exitRecord.processStartedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    [void]$process.Start()
    $exitRecord.processId = $process.Id
    $exitRecord.state = "Running"
    Write-ProcessExitRecord -Path $resolvedProcessExitPath -Record $exitRecord

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $exitRecord.state = "TimedOut"
        $exitRecord.timedOut = $true
        $exitRecord.killedByHarness = $true
        $process.Kill()
        $process.WaitForExit()
    }

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $output = $stdout + [Environment]::NewLine + $stderr
    [System.IO.File]::WriteAllText(
        $logPath,
        $output,
        [System.Text.Encoding]::UTF8)
    Write-Host $output

    $exitRecord.exitCode = $process.ExitCode
    $exitRecord.exitCodeHex = Format-ExitCodeHex -ExitCode $process.ExitCode
    $exitRecord.successMarkerObserved = $output.Contains($SuccessMarker)

    if ($exitRecord.timedOut) {
        throw "Core Console timed out after $TimeoutSeconds seconds. Log: $logPath"
    }
    if ($process.ExitCode -ne 0) {
        $exitRecord.state = if ($process.ExitCode -lt 0) {
            "ProcessCrashed"
        } else {
            "ExitedNonZero"
        }
        throw "Core Console exited with code $($process.ExitCode) ($($exitRecord.exitCodeHex)). Log: $logPath"
    }
    if (-not $exitRecord.successMarkerObserved) {
        $exitRecord.state = "CommandFailed"
        throw "Success marker '$SuccessMarker' was not observed. Log: $logPath"
    }

    $exitRecord.state = "Succeeded"
    Write-Host "PASS: command smoke marker observed."
    Write-Host "Marker: $SuccessMarker"
    Write-Host "Assemblies: $($resolvedAssemblyPaths -join '; ')"
    Write-Host "Artifact directory: $workingDirectory"
}
catch {
    if ($exitRecord.state -eq "Starting" -or $exitRecord.state -eq "Running") {
        $exitRecord.state = "RunnerFailed"
    }
    $exitRecord.error = $_.Exception.ToString()
    throw
}
finally {
    if ($null -ne $stopwatch) {
        $stopwatch.Stop()
        $exitRecord.durationMilliseconds = $stopwatch.ElapsedMilliseconds
    }
    if ($null -ne $process -and $process.HasExited -and $null -eq $exitRecord.exitCode) {
        $exitRecord.exitCode = $process.ExitCode
        $exitRecord.exitCodeHex = Format-ExitCodeHex -ExitCode $process.ExitCode
    }
    $exitRecord.finishedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
    Write-ProcessExitRecord -Path $resolvedProcessExitPath -Record $exitRecord
    if ($null -ne $process) {
        $process.Dispose()
    }
}
