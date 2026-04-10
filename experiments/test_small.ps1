param(
  [int]$Ranks = 4,
  [string]$GraphOut = ".\outputs\graph.json",
  [string]$PartOut = ".\outputs\part.json",
  [string]$BuildDir = ".\build"
)

$ErrorActionPreference = "Stop"

# Resolve repository root relative to this script so it can run from any CWD
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

# Normalize important paths to be rooted at repo root if not absolute
if (-not [System.IO.Path]::IsPathRooted($GraphOut)) { $GraphOut = Join-Path $RootDir $GraphOut }
if (-not [System.IO.Path]::IsPathRooted($PartOut))  { $PartOut  = Join-Path $RootDir $PartOut }
if (-not [System.IO.Path]::IsPathRooted($BuildDir)) { $BuildDir = Join-Path $RootDir $BuildDir }

# Paths
$tiny = Join-Path $RootDir "tools/partition/testdata/tiny_graph.twojson"
$partition = Join-Path $RootDir "tools/partition/run.py"
$validate = Join-Path $RootDir "tools/partition/validate.py"

# Ensure outputs dirs
$outDir = Join-Path $RootDir "outputs"
$testsDir = Join-Path $outDir "tests"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
if (-not (Test-Path $testsDir)) { New-Item -ItemType Directory -Path $testsDir | Out-Null }

# 1) Prepare tiny two-line JSON graph
Copy-Item -Force $tiny $GraphOut
Write-Host "[test_small.ps1] Copied tiny graph from $tiny to $GraphOut"

# 2) Partition for Ranks (use 'py' per env preference)
py $partition $GraphOut --ranks $Ranks --out $PartOut
py $validate $PartOut

# 3) Build runtime if needed
$exe = Join-Path $BuildDir "ngs_mpi.exe"
if (-not (Test-Path $exe)) {
  $srcDir = Join-Path $RootDir "mpi_runtime"
  cmake -S $srcDir -B $BuildDir -DCMAKE_BUILD_TYPE=Release
  cmake --build $BuildDir -j
  if (-not (Test-Path $exe)) { $exe = Join-Path $BuildDir "ngs_mpi" }
}
if (-not (Test-Path $exe)) { throw "ngs_mpi executable not found in $BuildDir" }

# 4) Run leader election and validate leader==max node id
mpirun -n $Ranks $exe `
  --graph $GraphOut `
  --part $PartOut `
  --algo leader `
  --rounds 50 `
  --log $outDir/

$summaryLeader = Join-Path $outDir "summary_leader.json"
if (-not (Test-Path $summaryLeader)) {
  "[test_small.ps1] ERROR: summary_leader.json not found" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
  exit 2
}

# Parse leader id from summary
$leaderLine = Select-String -Path $summaryLeader -Pattern '"leader"\s*:\s*([0-9]+)' | Select-Object -First 1
if (-not $leaderLine) {
  "[test_small.ps1] ERROR: Could not parse leader id" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
  exit 2
}
$leader = [int]($leaderLine.Matches[0].Groups[1].Value)
if ($leader -ne 5) {
  "[test_small.ps1] ERROR: Expected leader 5, got $leader" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
  exit 3
}
"[test_small.ps1] Leader test passed (leader=$leader)" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null

# 5) Run Dijkstra and validate distances + histogram
mpirun --oversubscribe -n $Ranks $exe `
  --graph $GraphOut `
  --part $PartOut `
  --algo dijkstra `
  --source 0 `
  --log $outDir/

$summaryD = Join-Path $outDir "summary_dijkstra.json"
if (-not (Test-Path $summaryD)) {
  "[test_small.ps1] ERROR: summary_dijkstra.json not found" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
  exit 4
}
# Parse JSON and validate expected distances from source 0
$data = Get-Content $summaryD -Raw | ConvertFrom-Json
$dm = $data.result.dist_map
$exp = @{ "0"=0.0; "1"=2.0; "2"=4.0; "3"=1.0; "4"=3.0; "5"=5.0 }
foreach ($k in $exp.Keys) {
  if (-not $dm.ContainsKey($k)) {
    "[test_small.ps1] ERROR: missing distance for node $k" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
    exit 4
  }
  $dv = [double]$dm.$k
  if ([math]::Abs($dv - [double]$exp[$k]) -gt 1e-6) {
    "[test_small.ps1] ERROR: distance mismatch for node $k: got $dv expected $($exp[$k])" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
    exit 4
  }
}
if ($null -eq $data.distance_histogram) {
  "[test_small.ps1] ERROR: missing distance_histogram in summary_dijkstra.json" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
  exit 4
}
"[test_small.ps1] Dijkstra distances and histogram validated" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null

# 6) Repeat with single-line tiny_graph.json to exercise loader robustness
$single = Join-Path $RootDir "tools/partition/testdata/tiny_graph.json"
Copy-Item -Force $single $GraphOut
py $partition $GraphOut --ranks $Ranks --out $PartOut
py $validate $PartOut
mpirun --oversubscribe -n $Ranks $exe `
  --graph $GraphOut `
  --part $PartOut `
  --algo dijkstra `
  --source 0 `
  --log $outDir/
$data = Get-Content $summaryD -Raw | ConvertFrom-Json
$dm = $data.result.dist_map
foreach ($k in $exp.Keys) {
  $dv = [double]$dm.$k
  if ([math]::Abs($dv - [double]$exp[$k]) -gt 1e-6) {
    "[test_small.ps1] ERROR: single-line loader distance mismatch for node $k: got $dv expected $($exp[$k])" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
    exit 4
  }
}
"[test_small.ps1] Single-line loader robustness validated" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null

# 7) Negative test: rank mismatch (partition says $Ranks, run with 3) should fail
$rc = 0
try {
  mpirun --oversubscribe -n 3 $exe `
    --graph $GraphOut `
    --part $PartOut `
    --algo leader `
    --rounds 10 `
    --log $outDir/
  $rc = $LASTEXITCODE
} catch { $rc = 1 }
if ($rc -eq 0) {
  "[test_small.ps1] ERROR: expected rank mismatch failure (rc should be non-zero)" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
  exit 5
} else {
  "[test_small.ps1] Rank mismatch negative test passed (rc=$rc)" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
}

# 8) Negative test: malformed graph (only one array) should fail to load
$badGraph = Join-Path $outDir "graph_bad.json"
(Get-Content $single -TotalCount 1) | Set-Content $badGraph
$rc2 = 0
try {
  mpirun --oversubscribe -n $Ranks $exe `
    --graph $badGraph `
    --part $PartOut `
    --algo leader `
    --rounds 10 `
    --log $outDir/
  $rc2 = $LASTEXITCODE
} catch { $rc2 = 1 }
if ($rc2 -eq 0) {
  "[test_small.ps1] ERROR: expected malformed-graph failure (rc should be non-zero)" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
  exit 6
} else {
  "[test_small.ps1] Malformed-graph negative test passed (rc=$rc2)" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
}

"[test_small.ps1] ALL CHECKS PASSED" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
