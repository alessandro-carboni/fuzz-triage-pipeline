param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet(
        "build",
        "shell",
        "fuzz",
        "demo-crash",
        "repro",
        "triage",
        "minimize",
        "logs",
        "meta",
        "report",
        "report-json",
        "crashes",
        "repro-log",
        "repro-meta",
        "minimize-log",
        "minimize-meta",
        "runs",
        "repros",
        "minimized",
        "reports",
        "get-id",
        "delete",
        "help",
        "summary",
        "status",
        "coverage",
        "coverage-summary",
        "coverage-replay-log"
    )]
    [string]$cmd,

    [Parameter(Position = 1)]
    [string]$target = "",

    [Parameter(Position = 2)]
    [int]$seconds = 0,

    [string]$crash = "",
    [string]$run = "",
    [int]$timeout = 20,
    [string]$targetRef = "",
    [string]$Id = "",

    [switch]$Last,
    [switch]$All
)

$image = "fuzzpipe"

$script:SupportedTargets = @("cjson", "yaml", "sqlite")

function Get-SupportedTargets {
    return $script:SupportedTargets
}

function Get-SupportedTargetsDisplay {
    return (Get-SupportedTargets) -join ", "
}

function Assert-TargetSupported {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    $supported = Get-SupportedTargets
    if ($supported -notcontains $TargetName) {
        throw "Unsupported target: $TargetName. Supported targets: $(Get-SupportedTargetsDisplay)"
    }
}

function Resolve-RequiredTarget {
    param(
        [string]$TargetName
    )

    if ([string]::IsNullOrWhiteSpace($TargetName)) {
        throw "Target required for command '$cmd'. Supported targets: $(Get-SupportedTargetsDisplay)"
    }

    Assert-TargetSupported -TargetName $TargetName
    return $TargetName
}

function Show-CommandSummary {
    Write-Host ""
    Write-Host "Command summary:"
    Write-Host "  build           Build Docker image"
    Write-Host "  shell           Open interactive shell in container"
    Write-Host "  fuzz            Run normal fuzzing"
    Write-Host "  demo-crash      Run controlled demo crash"
    Write-Host "  repro           Reproduce a crash"
    Write-Host "  minimize        Minimize a crashing input"
    Write-Host "  triage          Generate triage report"
    Write-Host "  status          Show compact status of latest run"
    Write-Host ""
    Write-Host "  runs            List run directories"
    Write-Host "  repros          List repro directories"
    Write-Host "  minimized       List minimized directories"
    Write-Host "  reports         List report directories"
    Write-Host ""
    Write-Host "  logs            Show latest run log"
    Write-Host "  meta            Show latest run metadata"
    Write-Host "  crashes         Show crashes in latest run"
    Write-Host "  report          Show latest markdown report"
    Write-Host "  report-json     Show latest JSON report"
    Write-Host "  repro-log       Show latest repro log"
    Write-Host "  repro-meta      Show latest repro metadata"
    Write-Host "  minimize-log    Show latest minimize log"
    Write-Host "  minimize-meta   Show latest minimize metadata"
    Write-Host ""
    Write-Host "  get-id          Show latest run id or list all run ids"
    Write-Host "  delete          Delete latest run / specific run / all artifacts"
    Write-Host "  help            Show usage"
    Write-Host "  summary         Show short command summary"
    Write-Host "  coverage        List coverage directories"
    Write-Host "  coverage-summary Show latest coverage summary"
    Write-Host "  coverage-replay-log Show latest coverage replay log"
    Write-Host ""
}

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  .\fuzz\run.ps1 build"
    Write-Host "  .\fuzz\run.ps1 shell"
    Write-Host "  .\fuzz\run.ps1 help"
    Write-Host "  .\fuzz\run.ps1 summary"
    Write-Host "  supported targets: $(Get-SupportedTargetsDisplay)"
    Write-Host ""
    Write-Host "Target-based commands always require an explicit target."
    Write-Host ""
    Write-Host "  .\fuzz\run.ps1 fuzz <target> [seconds] [-targetRef <ref>]"
    Write-Host "      example: .\fuzz\run.ps1 fuzz cjson 30 -targetRef v1.7.17"
    Write-Host "      example: .\fuzz\run.ps1 fuzz cjson 30 -targetRef v1.5.0"
    Write-Host "      example: .\fuzz\run.ps1 fuzz sqlite 30 -targetRef 3.51.3"
    Write-Host ""
    Write-Host "  .\fuzz\run.ps1 demo-crash <target> [seconds] [-targetRef <ref>]"
    Write-Host "      example: .\fuzz\run.ps1 demo-crash cjson 5 -targetRef v1.7.17"
    Write-Host "      example: .\fuzz\run.ps1 demo-crash cjson 5 -targetRef v1.5.0"
    Write-Host "      example: .\fuzz\run.ps1 demo-crash yaml 5"
    Write-Host ""
    Write-Host "  .\fuzz\run.ps1 repro <target> -crash <path>"
    Write-Host "  .\fuzz\run.ps1 minimize <target> -crash <path>"
    Write-Host "  .\fuzz\run.ps1 triage <target> -run <run_dir> [-timeout <sec>]"
    Write-Host ""
    Write-Host "Quick commands:"
    Write-Host "  .\fuzz\run.ps1 triage <target> -Last"
    Write-Host "  .\fuzz\run.ps1 repro <target> -Last"
    Write-Host "  .\fuzz\run.ps1 minimize <target> -Last"
    Write-Host "  .\fuzz\run.ps1 logs <target> -Last"
    Write-Host "  .\fuzz\run.ps1 meta <target> -Last"
    Write-Host "  .\fuzz\run.ps1 report <target> -Last"
    Write-Host "  .\fuzz\run.ps1 report-json <target> -Last"
    Write-Host "  .\fuzz\run.ps1 crashes <target> -Last"
    Write-Host "  .\fuzz\run.ps1 repro-log <target> -Last"
    Write-Host "  .\fuzz\run.ps1 repro-meta <target> -Last"
    Write-Host "  .\fuzz\run.ps1 minimize-log <target> -Last"
    Write-Host "  .\fuzz\run.ps1 minimize-meta <target> -Last"
    Write-Host "  .\fuzz\run.ps1 get-id <target> -Last"
    Write-Host "  .\fuzz\run.ps1 status <target> -Last"
    Write-Host "  .\fuzz\run.ps1 coverage <target> -Last"
    Write-Host "  .\fuzz\run.ps1 coverage-summary <target> -Last"
    Write-Host "  .\fuzz\run.ps1 coverage-replay-log <target> -Last"
    Write-Host ""
    Write-Host "Artifact listings:"
    Write-Host "  .\fuzz\run.ps1 runs <target>"
    Write-Host "  .\fuzz\run.ps1 runs <target> -Last"
    Write-Host "  .\fuzz\run.ps1 repros <target>"
    Write-Host "  .\fuzz\run.ps1 repros <target> -Last"
    Write-Host "  .\fuzz\run.ps1 minimized <target>"
    Write-Host "  .\fuzz\run.ps1 minimized <target> -Last"
    Write-Host "  .\fuzz\run.ps1 reports <target>"
    Write-Host "  .\fuzz\run.ps1 reports <target> -Last"
    Write-Host "  .\fuzz\run.ps1 coverage <target>"
    Write-Host "  .\fuzz\run.ps1 coverage <target> -Last"
    Write-Host ""
    Write-Host "Deletion:"
    Write-Host "  .\fuzz\run.ps1 delete <target> -Last"
    Write-Host "  .\fuzz\run.ps1 delete <target> -Id <run_id>"
    Write-Host "  .\fuzz\run.ps1 delete <target> -All"
    Write-Host ""
    Write-Host "Optional environment variables passed through to the container if set:"
    Write-Host "  FUZZPIPE_SANITIZERS, ASAN_OPTIONS, UBSAN_OPTIONS, ASAN_SYMBOLIZER_PATH, FUZZPIPE_ENABLE_COVERAGE"
    Show-CommandSummary
}

function Normalize-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    $normalized = $PathValue -replace '\\', '/'
    $normalized = $normalized -replace '^\./', ''
    $normalized = $normalized -replace '^\.\\', ''
    $normalized = $normalized.Trim()
    $normalized = $normalized.TrimEnd('/')

    return $normalized
}

function Get-TargetRootPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseRelativePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Assert-TargetSupported -TargetName $TargetName
    return Join-Path $PWD "$BaseRelativePath\$TargetName"
}

function Get-LatestDirectoryFromRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$EmptyRootMessage,

        [Parameter(Mandatory = $true)]
        [string]$EmptyDirMessage
    )

    if (-not (Test-Path $RootPath)) {
        throw $EmptyRootMessage
    }

    $latest = Get-ChildItem $RootPath -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) {
        throw $EmptyDirMessage
    }

    return $latest
}

function Get-LatestRunDir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Assert-TargetSupported -TargetName $TargetName

    $runsRoot = Get-TargetRootPath -BaseRelativePath "artifacts\runs" -TargetName $TargetName
    return Get-LatestDirectoryFromRoot `
        -RootPath $runsRoot `
        -EmptyRootMessage "No runs directory found for target: $TargetName" `
        -EmptyDirMessage "No run directories found for target: $TargetName"
}

function Get-LatestCrashFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Assert-TargetSupported -TargetName $TargetName

    $latestRun = Get-LatestRunDir $TargetName
    $crashDir = Join-Path $latestRun.FullName "crashes"

    if (-not (Test-Path $crashDir)) {
        throw "Crash directory not found: $crashDir"
    }

    $latestCrash = Get-ChildItem $crashDir -File | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latestCrash) {
        throw "No crash files found in latest run: $($latestRun.Name)"
    }

    return $latestCrash
}

function Get-LatestReproDir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Assert-TargetSupported -TargetName $TargetName

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\repros" -TargetName $TargetName
    return Get-LatestDirectoryFromRoot `
        -RootPath $root `
        -EmptyRootMessage "No repros directory found for target: $TargetName" `
        -EmptyDirMessage "No repro directories found for target: $TargetName"
}

function Get-LatestMinimizeDir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Assert-TargetSupported -TargetName $TargetName

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\minimized" -TargetName $TargetName
    return Get-LatestDirectoryFromRoot `
        -RootPath $root `
        -EmptyRootMessage "No minimized directory found for target: $TargetName" `
        -EmptyDirMessage "No minimize directories found for target: $TargetName"
}

function Get-LatestReportDir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Assert-TargetSupported -TargetName $TargetName

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\reports" -TargetName $TargetName
    return Get-LatestDirectoryFromRoot `
        -RootPath $root `
        -EmptyRootMessage "No reports directory found for target: $TargetName" `
        -EmptyDirMessage "No report directories found for target: $TargetName"
}

function Get-LatestCoverageDir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Assert-TargetSupported -TargetName $TargetName

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\coverage" -TargetName $TargetName
    return Get-LatestDirectoryFromRoot `
        -RootPath $root `
        -EmptyRootMessage "No coverage directory found for target: $TargetName" `
        -EmptyDirMessage "No coverage runs found for target: $TargetName"
}

function Get-CommonDockerArgs {
    $args = @(
        "run",
        "-it",
        "--rm",
        "-e", "DOCKER_IMAGE_TAG=$image`:latest",
        "-v", "${PWD}:/workspace"
    )

    if (-not [string]::IsNullOrWhiteSpace($env:FUZZPIPE_SANITIZERS)) {
        $args += @("-e", "FUZZPIPE_SANITIZERS=$($env:FUZZPIPE_SANITIZERS)")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ASAN_OPTIONS)) {
        $args += @("-e", "ASAN_OPTIONS=$($env:ASAN_OPTIONS)")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:FUZZPIPE_ENABLE_COVERAGE)) {
        $args += @("-e", "FUZZPIPE_ENABLE_COVERAGE=$($env:FUZZPIPE_ENABLE_COVERAGE)")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:UBSAN_OPTIONS)) {
        $args += @("-e", "UBSAN_OPTIONS=$($env:UBSAN_OPTIONS)")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ASAN_SYMBOLIZER_PATH)) {
        $args += @("-e", "ASAN_SYMBOLIZER_PATH=$($env:ASAN_SYMBOLIZER_PATH)")
    }

    $args += $image
    return $args
}

function Invoke-InContainer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShellCommand
    )

    $dockerArgs = Get-CommonDockerArgs
    $dockerArgs += @("bash", "-lc", $ShellCommand)

    & docker @dockerArgs
    exit $LASTEXITCODE
}

function Get-BootstrapCommand {
    return "chmod +x scripts/diagnostics_env.sh scripts/target_common.sh scripts/target_fetch_common.sh scripts/target_build_common.sh fuzz/fuzz.sh triage/repro.sh triage/minimize.sh && find targets -type f \( -name fetch.sh -o -name build.sh \) -exec chmod +x {} +"
}

function Get-RelativeCrashWorkspacePath {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$CrashFile
    )

    $relativeCrashPath = $CrashFile.FullName.Replace($PWD.Path, "").TrimStart('\')
    return Normalize-RepoPath $relativeCrashPath
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        return Get-Content $Path -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Show-LatestOrList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [switch]$UseLast
    )

    if (-not (Test-Path $RootPath)) {
        Write-Host "[+] Path not found: $RootPath"
        return
    }

    if ($UseLast) {
        $latest = Get-ChildItem $RootPath -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) {
            $latest
        }
        else {
            Write-Host "[+] No directories found in: $RootPath"
        }
        return
    }

    $items = Get-ChildItem $RootPath -Directory | Sort-Object Name -Descending
    if (-not $items) {
        Write-Host "[+] No directories found in: $RootPath"
        return
    }

    $items
}

function Get-RunIds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Assert-TargetSupported -TargetName $TargetName

    $runsRoot = Get-TargetRootPath -BaseRelativePath "artifacts\runs" -TargetName $TargetName
    if (-not (Test-Path $runsRoot)) {
        return [string[]]@()
    }

    $items = @(Get-ChildItem $runsRoot -Directory | Sort-Object Name -Descending | ForEach-Object { $_.Name })
    return [string[]]$items
}

function Get-RelatedArtifactDirsForRun {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName,

        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    Assert-TargetSupported -TargetName $TargetName

    $result = [ordered]@{
        RunDir       = Join-Path (Get-TargetRootPath -BaseRelativePath "artifacts\runs" -TargetName $TargetName) $RunId
        ReportDir    = Join-Path (Get-TargetRootPath -BaseRelativePath "artifacts\reports" -TargetName $TargetName) $RunId
        ReproDirs    = @()
        MinimizeDirs = @()
    }

    $workspaceRunFragment = "/artifacts/runs/$TargetName/$RunId/"
    $reproRoot = Get-TargetRootPath -BaseRelativePath "artifacts\repros" -TargetName $TargetName
    $minRoot = Get-TargetRootPath -BaseRelativePath "artifacts\minimized" -TargetName $TargetName

    if (Test-Path $reproRoot) {
        foreach ($dir in Get-ChildItem $reproRoot -Directory) {
            $meta = Read-JsonFile (Join-Path $dir.FullName "repro_meta.json")
            if ($null -eq $meta) { continue }

            $metaRunId = [string]$meta.run_id
            $metaCrashPath = [string]$meta.crash_path

            if ($metaRunId -eq $RunId -or $metaCrashPath -like "*$workspaceRunFragment*") {
                $result.ReproDirs += $dir.FullName
            }
        }
    }

    if (Test-Path $minRoot) {
        foreach ($dir in Get-ChildItem $minRoot -Directory) {
            $meta = Read-JsonFile (Join-Path $dir.FullName "minimize_meta.json")
            if ($null -eq $meta) { continue }

            $metaRunId = [string]$meta.run_id
            $metaCrashPath = [string]$meta.crash_path

            if ($metaRunId -eq $RunId -or $metaCrashPath -like "*$workspaceRunFragment*") {
                $result.MinimizeDirs += $dir.FullName
            }
        }
    }

    return $result
}

function Remove-DirectoryIfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
        Write-Host "[+] Deleted: $Path"
    }
}

function Remove-RunArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName,

        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    Assert-TargetSupported -TargetName $TargetName

    $related = Get-RelatedArtifactDirsForRun -TargetName $TargetName -RunId $RunId

    foreach ($dir in $related.ReproDirs) {
        Remove-DirectoryIfExists $dir
    }

    foreach ($dir in $related.MinimizeDirs) {
        Remove-DirectoryIfExists $dir
    }

    Remove-DirectoryIfExists $related.ReportDir
    Remove-DirectoryIfExists $related.RunDir
}

function Get-RunCrashCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDir
    )

    $crashDir = Join-Path $RunDir "crashes"
    if (-not (Test-Path $crashDir)) {
        return 0
    }

    return (Get-ChildItem $crashDir -File | Measure-Object).Count
}

function Get-RelatedLatestReproMeta {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName,

        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    Assert-TargetSupported -TargetName $TargetName

    $reproRoot = Get-TargetRootPath -BaseRelativePath "artifacts\repros" -TargetName $TargetName
    if (-not (Test-Path $reproRoot)) {
        return $null
    }

    $items = @()

    foreach ($dir in Get-ChildItem $reproRoot -Directory) {
        $metaPath = Join-Path $dir.FullName "repro_meta.json"
        $meta = Read-JsonFile $metaPath
        if ($null -eq $meta) { continue }

        if ([string]$meta.run_id -eq $RunId) {
            $items += [PSCustomObject]@{
                Dir  = $dir
                Meta = $meta
            }
        }
    }

    if ($items.Count -eq 0) {
        return $null
    }

    return ($items | Sort-Object { $_.Dir.Name } -Descending | Select-Object -First 1)
}

function Get-RelatedLatestMinimizeMeta {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName,

        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    Assert-TargetSupported -TargetName $TargetName

    $minRoot = Get-TargetRootPath -BaseRelativePath "artifacts\minimized" -TargetName $TargetName
    if (-not (Test-Path $minRoot)) {
        return $null
    }

    $items = @()

    foreach ($dir in Get-ChildItem $minRoot -Directory) {
        $metaPath = Join-Path $dir.FullName "minimize_meta.json"
        $meta = Read-JsonFile $metaPath
        if ($null -eq $meta) { continue }

        if ([string]$meta.run_id -eq $RunId) {
            $items += [PSCustomObject]@{
                Dir  = $dir
                Meta = $meta
            }
        }
    }

    if ($items.Count -eq 0) {
        return $null
    }

    return ($items | Sort-Object { $_.Dir.Name } -Descending | Select-Object -First 1)
}

function Show-Status {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Assert-TargetSupported -TargetName $TargetName

    $latestRun = Get-LatestRunDir $TargetName
    $metaPath = Join-Path $latestRun.FullName "meta.json"
    $meta = Read-JsonFile $metaPath

    $runId = $latestRun.Name
    $crashCount = Get-RunCrashCount -RunDir $latestRun.FullName

    $reportDir = Join-Path (Get-TargetRootPath -BaseRelativePath "artifacts\reports" -TargetName $TargetName) $runId
    $reportJsonPath = Join-Path $reportDir "report.json"
    $reportPresent = Test-Path $reportJsonPath

    $reproInfo = Get-RelatedLatestReproMeta -TargetName $TargetName -RunId $runId
    $minInfo = Get-RelatedLatestMinimizeMeta -TargetName $TargetName -RunId $runId

    $reproPresent = $null -ne $reproInfo
    $minPresent = $null -ne $minInfo

    $mode = if ($meta) { [string]$meta.mode } else { "unknown" }
    $targetRefValue = if ($meta) { [string]$meta.target_ref } else { "unknown" }
    $targetVersion = if ($meta) { [string]$meta.target_version } else { "unknown" }

    $lastReproStatus = if ($reproPresent) { [string]$reproInfo.Meta.repro_status } else { "absent" }
    $lastReproExit = if ($reproPresent) { [string]$reproInfo.Meta.exit_code } else { "-" }

    $lastMinStatus = if ($minPresent) { [string]$minInfo.Meta.minimize_status } else { "absent" }
    $lastMinExit = if ($minPresent) { [string]$minInfo.Meta.exit_code } else { "-" }

    Write-Host ""
    Write-Host "========== FUZZPIPE STATUS =========="
    Write-Host "Target           : $TargetName"
    Write-Host "Latest run id    : $runId"
    Write-Host "Mode             : $mode"
    Write-Host "Target ref       : $targetRefValue"
    Write-Host "Target version   : $targetVersion"
    Write-Host "Crashes          : $crashCount"
    Write-Host "Report           : $(if ($reportPresent) { 'present' } else { 'absent' })"
    Write-Host "Repro            : $(if ($reproPresent) { 'present' } else { 'absent' })"
    Write-Host "Repro status     : $lastReproStatus"
    Write-Host "Repro exit code  : $lastReproExit"
    Write-Host "Minimize         : $(if ($minPresent) { 'present' } else { 'absent' })"
    Write-Host "Minimize status  : $lastMinStatus"
    Write-Host "Minimize exit    : $lastMinExit"
    Write-Host "Run path         : $($latestRun.FullName)"


    if ($reportPresent) {
        Write-Host "Report path      : $reportJsonPath"
    }

    if ($reproPresent) {
        Write-Host "Repro path       : $($reproInfo.Dir.FullName)"
    }

    if ($minPresent) {
        Write-Host "Minimize path    : $($minInfo.Dir.FullName)"
    }

    Write-Host "====================================="
    Write-Host ""
}

if ($cmd -eq "build") {
    docker build -t $image -f docker/Dockerfile .
}
elseif ($cmd -eq "shell") {
    $dockerArgs = Get-CommonDockerArgs
    $dockerArgs += @("bash")
    & docker @dockerArgs
    exit $LASTEXITCODE
}
elseif ($cmd -eq "fuzz") {
    $target = Resolve-RequiredTarget $target

    $envCmd = ""
    if ($seconds -gt 0) { $envCmd = "MAX_TOTAL_TIME=$seconds " }

    $targetRefEnv = ""
    if (-not [string]::IsNullOrWhiteSpace($targetRef)) { $targetRefEnv = "TARGET_REF=$targetRef " }

    $bootstrap = Get-BootstrapCommand
    Invoke-InContainer "$bootstrap && ${envCmd}${targetRefEnv}./fuzz/fuzz.sh $target"
}
elseif ($cmd -eq "demo-crash") {
    $target = Resolve-RequiredTarget $target

    $sec = $seconds
    if ($sec -le 0) { $sec = 5 }
    $envCmd = "MAX_TOTAL_TIME=$sec "

    $targetRefEnv = ""
    if (-not [string]::IsNullOrWhiteSpace($targetRef)) { $targetRefEnv = "TARGET_REF=$targetRef " }

    $bootstrap = Get-BootstrapCommand
    Invoke-InContainer "$bootstrap && ${envCmd}${targetRefEnv}./fuzz/fuzz.sh $target demo-crash"
}
elseif ($cmd -eq "repro") {
    $target = Resolve-RequiredTarget $target

    $bootstrap = Get-BootstrapCommand

    if ($Last) {
        $latestCrash = Get-LatestCrashFile $target
        $crashPath = Get-RelativeCrashWorkspacePath $latestCrash
        Invoke-InContainer "$bootstrap && ./triage/repro.sh $target /workspace/$crashPath"
    }
    else {
        if ([string]::IsNullOrWhiteSpace($crash)) {
            Show-Usage
            exit 1
        }

        $crashPath = Normalize-RepoPath $crash
        Invoke-InContainer "$bootstrap && ./triage/repro.sh $target /workspace/$crashPath"
    }
}
elseif ($cmd -eq "minimize") {
    $target = Resolve-RequiredTarget $target

    $bootstrap = Get-BootstrapCommand

    if ($Last) {
        $latestCrash = Get-LatestCrashFile $target
        $crashPath = Get-RelativeCrashWorkspacePath $latestCrash
        Invoke-InContainer "$bootstrap && ./triage/minimize.sh $target /workspace/$crashPath"
    }
    else {
        if ([string]::IsNullOrWhiteSpace($crash)) {
            Show-Usage
            exit 1
        }

        $crashPath = Normalize-RepoPath $crash
        Invoke-InContainer "$bootstrap && ./triage/minimize.sh $target /workspace/$crashPath"
    }
}
elseif ($cmd -eq "triage") {
    $target = Resolve-RequiredTarget $target

    $bootstrap = Get-BootstrapCommand

    if ($Last) {
        Invoke-InContainer "$bootstrap && python3 triage/triage.py --target $target --last --timeout $timeout"
    }
    else {
        if ([string]::IsNullOrWhiteSpace($run)) {
            Show-Usage
            exit 1
        }

        $runPath = Normalize-RepoPath $run
        Invoke-InContainer "$bootstrap && python3 triage/triage.py --target $target --run $runPath --timeout $timeout"
    }
}
elseif ($cmd -eq "logs") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRun = Get-LatestRunDir $target
    Get-Content (Join-Path $latestRun.FullName "run.log")
}
elseif ($cmd -eq "meta") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRun = Get-LatestRunDir $target
    Get-Content (Join-Path $latestRun.FullName "meta.json")
}
elseif ($cmd -eq "report") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRun = Get-LatestRunDir $target
    $reportPath = Join-Path $PWD "artifacts\reports\$target\$($latestRun.Name)\report.md"

    if (-not (Test-Path $reportPath)) {
        Write-Host "[+] Report not found: $reportPath"
        exit 0
    }

    Get-Content $reportPath
}
elseif ($cmd -eq "report-json") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRun = Get-LatestRunDir $target
    $reportPath = Join-Path $PWD "artifacts\reports\$target\$($latestRun.Name)\report.json"

    if (-not (Test-Path $reportPath)) {
        Write-Host "[+] Report JSON not found: $reportPath"
        exit 0
    }

    Get-Content $reportPath
}
elseif ($cmd -eq "coverage-replay-log") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestCoverage = Get-LatestCoverageDir $target
    $logPath = Join-Path $latestCoverage.FullName "coverage-replay.log"

    if (-not (Test-Path $logPath)) {
        Write-Host "[+] Coverage replay log not found: $logPath"
        exit 0
    }

    Get-Content $logPath
}
elseif ($cmd -eq "crashes") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRun = Get-LatestRunDir $target
    $crashDir = Join-Path $latestRun.FullName "crashes"

    if (-not (Test-Path $crashDir)) {
        Write-Host "[+] Crash directory not found: $crashDir"
        exit 0
    }

    Get-ChildItem $crashDir
}
elseif ($cmd -eq "repro-log") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRepro = Get-LatestReproDir $target
    Get-Content (Join-Path $latestRepro.FullName "repro.log")
}
elseif ($cmd -eq "repro-meta") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRepro = Get-LatestReproDir $target
    Get-Content (Join-Path $latestRepro.FullName "repro_meta.json")
}
elseif ($cmd -eq "minimize-log") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestMin = Get-LatestMinimizeDir $target
    Get-Content (Join-Path $latestMin.FullName "minimize.log")
}
elseif ($cmd -eq "minimize-meta") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestMin = Get-LatestMinimizeDir $target
    Get-Content (Join-Path $latestMin.FullName "minimize_meta.json")
}
elseif ($cmd -eq "runs") {
    $target = Resolve-RequiredTarget $target

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\runs" -TargetName $target
    Show-LatestOrList -RootPath $root -UseLast:$Last
}
elseif ($cmd -eq "repros") {
    $target = Resolve-RequiredTarget $target

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\repros" -TargetName $target
    Show-LatestOrList -RootPath $root -UseLast:$Last
}
elseif ($cmd -eq "minimized") {
    $target = Resolve-RequiredTarget $target

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\minimized" -TargetName $target
    Show-LatestOrList -RootPath $root -UseLast:$Last
}
elseif ($cmd -eq "reports") {
    $target = Resolve-RequiredTarget $target

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\reports" -TargetName $target
    Show-LatestOrList -RootPath $root -UseLast:$Last
}
elseif ($cmd -eq "coverage-summary") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestCoverage = Get-LatestCoverageDir $target
    $summaryPath = Join-Path $latestCoverage.FullName "coverage-summary.txt"

    if (-not (Test-Path $summaryPath)) {
        Write-Host "[+] Coverage summary not found: $summaryPath"
        exit 0
    }

    Get-Content $summaryPath
}
elseif ($cmd -eq "coverage") {
    $target = Resolve-RequiredTarget $target

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\coverage" -TargetName $target
    Show-LatestOrList -RootPath $root -UseLast:$Last
}
elseif ($cmd -eq "get-id") {
    $target = Resolve-RequiredTarget $target

    $ids = @(Get-RunIds -TargetName $target)

    if ($ids.Count -eq 0) {
        Write-Host "[+] No run ids found for target: $target"
        exit 0
    }

    if ($Last) {
        Write-Host "$($ids[0])"
    }
    else {
        $ids
    }
}
elseif ($cmd -eq "status") {
    $target = Resolve-RequiredTarget $target

    if (-not $Last) {
        Show-Usage
        exit 1
    }

    Show-Status -TargetName $target
}
elseif ($cmd -eq "summary") {
    Show-CommandSummary
    exit 0
}
elseif ($cmd -eq "help") {
    Show-Usage
    exit 0
}
elseif ($cmd -eq "delete") {
    $target = Resolve-RequiredTarget $target

    if ($All) {
        Remove-DirectoryIfExists (Get-TargetRootPath -BaseRelativePath "artifacts\runs" -TargetName $target)
        Remove-DirectoryIfExists (Get-TargetRootPath -BaseRelativePath "artifacts\reports" -TargetName $target)
        Remove-DirectoryIfExists (Get-TargetRootPath -BaseRelativePath "artifacts\repros" -TargetName $target)
        Remove-DirectoryIfExists (Get-TargetRootPath -BaseRelativePath "artifacts\minimized" -TargetName $target)
        Remove-DirectoryIfExists (Get-TargetRootPath -BaseRelativePath "artifacts\coverage" -TargetName $target)
        exit 0
    }

    if ($Last) {
        $latestRun = Get-LatestRunDir $target
        Remove-RunArtifacts -TargetName $target -RunId $latestRun.Name
        exit 0
    }

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        Remove-RunArtifacts -TargetName $target -RunId $Id
        exit 0
    }

    Show-Usage
    exit 1
}
else {
    Show-Usage
    exit 1
}
