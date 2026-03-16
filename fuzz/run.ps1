param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("build", "shell", "fuzz", "demo-crash", "repro", "triage", "minimize")]
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
    [string]$targetRef = ""
)

$image = "fuzzpipe"

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  .\fuzz\run.ps1 build"
    Write-Host "  .\fuzz\run.ps1 shell"
    Write-Host "  .\fuzz\run.ps1 fuzz [target] [seconds] [-targetRef <ref>]"
    Write-Host "      example: .\fuzz\run.ps1 fuzz cjson 30 -targetRef v1.7.17"
    Write-Host "  .\fuzz\run.ps1 demo-crash [target] [seconds] [-targetRef <ref>]"
    Write-Host "      example: .\fuzz\run.ps1 demo-crash cjson 5 -targetRef v1.7.17"
    Write-Host "  .\fuzz\run.ps1 repro -target <target> -crash <path>"
    Write-Host "      example: .\fuzz\run.ps1 repro -target cjson -crash `"artifacts/runs/cjson/<run_id>/crashes/<file>`""
    Write-Host "  .\fuzz\run.ps1 minimize -target <target> -crash <path>"
    Write-Host "      example: .\fuzz\run.ps1 minimize -target cjson -crash `"artifacts/runs/cjson/<run_id>/crashes/<file>`""
    Write-Host "  .\fuzz\run.ps1 triage -target <target> -run <run_dir> [-timeout <sec>]"
    Write-Host "      example: .\fuzz\run.ps1 triage -target cjson -run `"artifacts/runs/cjson/<run_id>`" -timeout 20"
}

if ($cmd -eq "build") {
    docker build -t $image -f docker/Dockerfile .
}
elseif ($cmd -eq "shell") {
    docker run --rm -v ${PWD}:/workspace $image
}
elseif ($cmd -eq "fuzz") {
    $envCmd = ""
    if ($seconds -gt 0) { $envCmd = "MAX_TOTAL_TIME=$seconds " }

    $targetRefEnv = ""
    if (-not [string]::IsNullOrWhiteSpace($targetRef)) { $targetRefEnv = "TARGET_REF=$targetRef " }

    docker run -it --rm `
      -e DOCKER_IMAGE_TAG="$image:latest" `
      -v ${PWD}:/workspace `
      $image bash -lc "chmod +x fuzz/fuzz.sh targets/cjson/fetch.sh targets/cjson/build.sh && ${envCmd}${targetRefEnv}./fuzz/fuzz.sh $target"
}
elseif ($cmd -eq "demo-crash") {
    $sec = $seconds
    if ($sec -le 0) { $sec = 5 }
    $envCmd = "MAX_TOTAL_TIME=$sec "

    $targetRefEnv = ""
    if (-not [string]::IsNullOrWhiteSpace($targetRef)) { $targetRefEnv = "TARGET_REF=$targetRef " }

    docker run -it --rm `
      -e DOCKER_IMAGE_TAG="$image:latest" `
      -v ${PWD}:/workspace `
      $image bash -lc "chmod +x fuzz/fuzz.sh targets/cjson/fetch.sh targets/cjson/build.sh && ${envCmd}${targetRefEnv}./fuzz/fuzz.sh $target demo-crash"
}
elseif ($cmd -eq "repro") {
    if ([string]::IsNullOrWhiteSpace($crash)) {
        Show-Usage
        exit 1
    }

    $crashPath = $crash -replace '\\', '/'
    $crashPath = $crashPath -replace '^\./', ''
    $crashPath = $crashPath -replace '^\.\\', ''

    docker run -it --rm `
      -e DOCKER_IMAGE_TAG="$image:latest" `
      -v ${PWD}:/workspace `
      $image bash -lc "chmod +x triage/repro.sh && ./triage/repro.sh $target /workspace/$crashPath"
}
elseif ($cmd -eq "minimize") {
    if ([string]::IsNullOrWhiteSpace($crash)) {
        Show-Usage
        exit 1
    }

    $crashPath = $crash -replace '\\', '/'
    $crashPath = $crashPath -replace '^\./', ''
    $crashPath = $crashPath -replace '^\.\\', ''

    docker run -it --rm `
      -e DOCKER_IMAGE_TAG="$image:latest" `
      -v ${PWD}:/workspace `
      $image bash -lc "chmod +x triage/minimize.sh && ./triage/minimize.sh $target /workspace/$crashPath"
}
elseif ($cmd -eq "triage") {
    if ([string]::IsNullOrWhiteSpace($run)) {
        Show-Usage
        exit 1
    }

    $runPath = $run -replace '\\', '/'
    $runPath = $runPath -replace '^\./', ''
    $runPath = $runPath -replace '^\.\\', ''
    $runPath = $runPath.TrimEnd('/')

    docker run -it --rm `
      -e DOCKER_IMAGE_TAG="$image:latest" `
      -v ${PWD}:/workspace `
      $image bash -lc "python3 triage/triage.py --target $target --run $runPath --timeout $timeout"
}
else {
    Show-Usage
    exit 1
}