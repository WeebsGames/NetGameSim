param(
  [int]$Ranks = 10,
  [string]$Graph = ".\outputs\graph.json",
  [string]$Part = ".\outputs\part.json",
  [string]$BuildDir = ".\build",
  [int]$Rounds = 200
)

$ErrorActionPreference = "Stop"

# Auto-sync ranks with partition unless OVERRIDE_RANKS=1
try {
  if (Test-Path $Part) {
    $json = Get-Content $Part -Raw | ConvertFrom-Json
    $partRanks = [int]($json.meta.ranks)
    $override = [int]([Environment]::GetEnvironmentVariable("OVERRIDE_RANKS") | ForEach-Object { if ($_ -eq $null -or $_ -eq "") { 0 } else { $_ } })
    if ($override -ne 1 -and $partRanks -gt 0) { $Ranks = $partRanks }
  }
} catch { }

# Ensure build
if (-not (Test-Path (Join-Path $BuildDir "ngs_mpi.exe")) -and -not (Test-Path (Join-Path $BuildDir "ngs_mpi"))) {
  cmake -S mpi_runtime -B $BuildDir -DCMAKE_BUILD_TYPE=Release
  cmake --build $BuildDir -j
}

# Resolve executable path
$exe = Join-Path $BuildDir "ngs_mpi.exe"
if (-not (Test-Path $exe)) { $exe = Join-Path $BuildDir "ngs_mpi" }

# Run leader election
mpirun --oversubscribe -n $Ranks $exe `
  --graph $Graph `
  --part $Part `
  --algo leader `
  --rounds $Rounds `
  --log outputs/
