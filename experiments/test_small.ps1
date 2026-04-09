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

# 5) Run Dijkstra (placeholder until algorithm complete). Ensure summary exists.
mpirun -n $Ranks $exe `
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
"[test_small.ps1] Dijkstra placeholder run completed; summary present." | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null

"[test_small.ps1] ALL CHECKS PASSED" | Tee-Object -FilePath (Join-Path $testsDir "test_small_ps1.log") -Append | Out-Null
