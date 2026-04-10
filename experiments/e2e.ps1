param(
  [int]$Ranks = 10,
  [int]$Seed = -1,
  [string]$Config = ".\GenericSimUtilities\src\main\resources\application.conf"
)

$ErrorActionPreference = "Stop"

# Resolve repository root relative to this script so it can run from any CWD
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

# Paths
$OutDir = Join-Path $RootDir "outputs"
$GraphOut = Join-Path $OutDir "graph.json"
$PartOut = Join-Path $OutDir "part.json"
$GraphExportPs1 = Join-Path $RootDir "tools/graph_export/run.ps1"
$PartitionPy = Join-Path $RootDir "tools/partition/run.py"
$ValidatePy = Join-Path $RootDir "tools/partition/validate.py"
$RunLeader = Join-Path $RootDir "experiments/run_leader.ps1"
$RunDijk = Join-Path $RootDir "experiments/run_dijkstra.ps1"

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# 1) Graph export (honor optional Seed)
if ($Seed -ge 0) {
  Write-Host "[e2e.ps1] Exporting graph with Seed=$Seed"
  & $GraphExportPs1 -Config $Config -OutPath $GraphOut -Seed $Seed
} else {
  Write-Host "[e2e.ps1] Exporting graph (seed from config)"
  & $GraphExportPs1 -Config $Config -OutPath $GraphOut
}

# 2) Partition and validate
Write-Host "[e2e.ps1] Partitioning graph with ranks=$Ranks"
py $PartitionPy $GraphOut --ranks $Ranks --out $PartOut
py $ValidatePy $PartOut

# 3) Run leader and dijkstra (wrappers auto-sync -n to partition and use --oversubscribe)
Write-Host "[e2e.ps1] Running leader election"
& $RunLeader -Ranks $Ranks -Graph $GraphOut -Part $PartOut

Write-Host "[e2e.ps1] Running Dijkstra (source=0)"
& $RunDijk -Ranks $Ranks -Graph $GraphOut -Part $PartOut -Source 0

Write-Host "[e2e.ps1] Complete. Summaries at outputs/summary_leader.json and outputs/summary_dijkstra.json"