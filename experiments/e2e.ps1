param(
  [int]$Ranks = 10,
  [int]$Seed = -1,
  [string]$Config = ".\GenericSimUtilities\src\main\resources\application.conf",
  [string]$GraphOut = ".\outputs\graph.json",
  [string]$PartOut = ".\outputs\part.json"
)

$ErrorActionPreference = "Stop"

# Resolve repository root relative to this script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

# Normalize to absolute paths
if (-not [System.IO.Path]::IsPathRooted($GraphOut)) { $GraphOut = Join-Path $RootDir $GraphOut }
if (-not [System.IO.Path]::IsPathRooted($PartOut))  { $PartOut  = Join-Path $RootDir $PartOut }
if (-not [System.IO.Path]::IsPathRooted($Config))   { $Config   = Join-Path $RootDir $Config }

# Ensure outputs dirs
$outDir = Join-Path $RootDir "outputs"
$expDir = Join-Path $outDir "experiments"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
if (-not (Test-Path $expDir)) { New-Item -ItemType Directory -Path $expDir | Out-Null }

# 1) Generate graph
if ($Seed -ge 0) {
  & (Join-Path $RootDir "tools/graph_export/run.ps1") -Config $Config -OutPath $GraphOut -Seed $Seed
} else {
  & (Join-Path $RootDir "tools/graph_export/run.ps1") -Config $Config -OutPath $GraphOut
}

# 2) Partition and validate (use 'py' by default on Windows)
py (Join-Path $RootDir "tools/partition/run.py") $GraphOut --ranks $Ranks --out $PartOut
py (Join-Path $RootDir "tools/partition/validate.py") $PartOut

# 3) Run leader and dijkstra (wrappers auto-sync -n to partition and add --oversubscribe)
& (Join-Path $RootDir "experiments/run_leader.ps1")
& (Join-Path $RootDir "experiments/run_dijkstra.ps1")

# 4) Archive summaries
$tag = if ($Seed -ge 0) { "seed$Seed" } else { "untagged" }
$sumLeader = Join-Path $outDir "summary_leader.json"
$sumD = Join-Path $outDir "summary_dijkstra.json"
if (Test-Path $sumLeader) { Copy-Item -Force $sumLeader (Join-Path $expDir "summary_leader_${tag}.json") }
if (Test-Path $sumD)      { Copy-Item -Force $sumD      (Join-Path $expDir "summary_dijkstra_${tag}.json") }

Write-Host "[e2e.ps1] Completed. Summaries archived under outputs/experiments (if present)."