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
        "status"
    )]
    [string]$cmd,

    [Parameter(Position = 1)]
    [string]$target = "cjson",

    # Used by: fuzz / demo-crash (seconds)
    [Parameter(Position = 2)]
    [int]$seconds = 0,

    # Used by: repro / minimize
    [string]$crash = "",

    # Used by: triage (repo-relative run dir)
    [string]$run = "",

    # Used by: triage
    [int]$timeout = 20,

    # Used by: fuzz / demo-crash
    [string]$targetRef = "",

    # Used by: delete
    [string]$Id = "",

    # Generic selectors
    [switch]$Last,
    [switch]$All
)

$image = "fuzzpipe"

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
    Write-Host ""
}

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  .\fuzz\run.ps1 build"
    Write-Host "  .\fuzz\run.ps1 shell"
    Write-Host "  .\fuzz\run.ps1 help"
    Write-Host "  .\fuzz\run.ps1 summary"
    Write-Host "  .\fuzz\run.ps1 fuzz [target] [seconds] [-targetRef <ref>]"
    Write-Host "      example: .\fuzz\run.ps1 fuzz cjson 30 -targetRef v1.7.17"
    Write-Host "  .\fuzz\run.ps1 demo-crash [target] [seconds] [-targetRef <ref>]"
    Write-Host "      example: .\fuzz\run.ps1 demo-crash cjson 5 -targetRef v1.7.17"
    Write-Host "  .\fuzz\run.ps1 repro -target <target> -crash <path>"
    Write-Host "  .\fuzz\run.ps1 minimize -target <target> -crash <path>"
    Write-Host "  .\fuzz\run.ps1 triage -target <target> -run <run_dir> [-timeout <sec>]"
    Write-Host ""
    Write-Host "Quick commands:"
    Write-Host "  .\fuzz\run.ps1 triage -Last"
    Write-Host "  .\fuzz\run.ps1 repro -Last"
    Write-Host "  .\fuzz\run.ps1 minimize -Last"
    Write-Host "  .\fuzz\run.ps1 logs -Last"
    Write-Host "  .\fuzz\run.ps1 meta -Last"
    Write-Host "  .\fuzz\run.ps1 report -Last"
    Write-Host "  .\fuzz\run.ps1 report-json -Last"
    Write-Host "  .\fuzz\run.ps1 crashes -Last"
    Write-Host "  .\fuzz\run.ps1 repro-log -Last"
    Write-Host "  .\fuzz\run.ps1 repro-meta -Last"
    Write-Host "  .\fuzz\run.ps1 minimize-log -Last"
    Write-Host "  .\fuzz\run.ps1 minimize-meta -Last"
    Write-Host "  .\fuzz\run.ps1 get-id -Last"
    Write-Host "  .\fuzz\run.ps1 status -Last"
    Write-Host ""
    Write-Host "Artifact listings:"
    Write-Host "  .\fuzz\run.ps1 runs"
    Write-Host "  .\fuzz\run.ps1 runs -Last"
    Write-Host "  .\fuzz\run.ps1 repros"
    Write-Host "  .\fuzz\run.ps1 repros -Last"
    Write-Host "  .\fuzz\run.ps1 minimized"
    Write-Host "  .\fuzz\run.ps1 minimized -Last"
    Write-Host "  .\fuzz\run.ps1 reports"
    Write-Host "  .\fuzz\run.ps1 reports -Last"
    Write-Host ""
    Write-Host "Deletion:"
    Write-Host "  .\fuzz\run.ps1 delete -Last"
    Write-Host "  .\fuzz\run.ps1 delete -Id <run_id>"
    Write-Host "  .\fuzz\run.ps1 delete -All"
    Write-Host ""
    Write-Host "Optional environment variables passed through to the container if set:"
    Write-Host "  FUZZPIPE_SANITIZERS, ASAN_OPTIONS, UBSAN_OPTIONS, ASAN_SYMBOLIZER_PATH"
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

    $root = Get-TargetRootPath -BaseRelativePath "artifacts\reports" -TargetName $TargetName
    return Get-LatestDirectoryFromRoot `
        -RootPath $root `
        -EmptyRootMessage "No reports directory found for target: $TargetName" `
        -EmptyDirMessage "No report directories found for target: $TargetName"
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
    return "chmod +x scripts/diagnostics_env.sh fuzz/fuzz.sh triage/repro.sh triage/minimize.sh targets/cjson/fetch.sh targets/cjson/build.sh targets/cjson_old/fetch.sh targets/cjson_old/build.sh"
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

    $result = [ordered]@{
        RunDir      = Join-Path (Get-TargetRootPath -BaseRelativePath "artifacts\runs" -TargetName $TargetName) $RunId
        ReportDir   = Join-Path (Get-TargetRootPath -BaseRelativePath "artifacts\reports" -TargetName $TargetName) $RunId
        ReproDirs   = @()
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
    $envCmd = ""
    if ($seconds -gt 0) { $envCmd = "MAX_TOTAL_TIME=$seconds " }

    $targetRefEnv = ""
    if (-not [string]::IsNullOrWhiteSpace($targetRef)) { $targetRefEnv = "TARGET_REF=$targetRef " }

    $bootstrap = Get-BootstrapCommand
    Invoke-InContainer "$bootstrap && ${envCmd}${targetRefEnv}./fuzz/fuzz.sh $target"
}
elseif ($cmd -eq "demo-crash") {
    $sec = $seconds
    if ($sec -le 0) { $sec = 5 }
    $envCmd = "MAX_TOTAL_TIME=$sec "

    $targetRefEnv = ""
    if (-not [string]::IsNullOrWhiteSpace($targetRef)) { $targetRefEnv = "TARGET_REF=$targetRef " }

    $bootstrap = Get-BootstrapCommand
    Invoke-InContainer "$bootstrap && ${envCmd}${targetRefEnv}./fuzz/fuzz.sh $target demo-crash"
}
elseif ($cmd -eq "repro") {
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
    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRun = Get-LatestRunDir $target
    Get-Content (Join-Path $latestRun.FullName "run.log")
}
elseif ($cmd -eq "meta") {
    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRun = Get-LatestRunDir $target
    Get-Content (Join-Path $latestRun.FullName "meta.json")
}
elseif ($cmd -eq "report") {
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
elseif ($cmd -eq "crashes") {
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
    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRepro = Get-LatestReproDir $target
    Get-Content (Join-Path $latestRepro.FullName "repro.log")
}
elseif ($cmd -eq "repro-meta") {
    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestRepro = Get-LatestReproDir $target
    Get-Content (Join-Path $latestRepro.FullName "repro_meta.json")
}
elseif ($cmd -eq "minimize-log") {
    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestMin = Get-LatestMinimizeDir $target
    Get-Content (Join-Path $latestMin.FullName "minimize.log")
}
elseif ($cmd -eq "minimize-meta") {
    if (-not $Last) {
        Show-Usage
        exit 1
    }

    $latestMin = Get-LatestMinimizeDir $target
    Get-Content (Join-Path $latestMin.FullName "minimize_meta.json")
}
elseif ($cmd -eq "runs") {
    $root = Get-TargetRootPath -BaseRelativePath "artifacts\runs" -TargetName $target
    Show-LatestOrList -RootPath $root -UseLast:$Last
}
elseif ($cmd -eq "repros") {
    $root = Get-TargetRootPath -BaseRelativePath "artifacts\repros" -TargetName $target
    Show-LatestOrList -RootPath $root -UseLast:$Last
}
elseif ($cmd -eq "minimized") {
    $root = Get-TargetRootPath -BaseRelativePath "artifacts\minimized" -TargetName $target
    Show-LatestOrList -RootPath $root -UseLast:$Last
}
elseif ($cmd -eq "reports") {
    $root = Get-TargetRootPath -BaseRelativePath "artifacts\reports" -TargetName $target
    Show-LatestOrList -RootPath $root -UseLast:$Last
}

elseif ($cmd -eq "get-id") {
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
    if ($All) {
        Remove-DirectoryIfExists (Get-TargetRootPath -BaseRelativePath "artifacts\runs" -TargetName $target)
        Remove-DirectoryIfExists (Get-TargetRootPath -BaseRelativePath "artifacts\reports" -TargetName $target)
        Remove-DirectoryIfExists (Get-TargetRootPath -BaseRelativePath "artifacts\repros" -TargetName $target)
        Remove-DirectoryIfExists (Get-TargetRootPath -BaseRelativePath "artifacts\minimized" -TargetName $target)
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