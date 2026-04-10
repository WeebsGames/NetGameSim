param(
  [string]$Config = ".\GenericSimUtilities\src\main\resources\application.conf",
  [string]$OutPath = ".\outputs\graph.json",
  [int]$Seed = -1,
  [string]$SbtCmd = "sbt"
)

# Ensure output directory exists
$outDir = Split-Path -Parent $OutPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
if (-not (Test-Path ".\outputs")) { New-Item -ItemType Directory -Path ".\outputs" | Out-Null }

# Force NetGameSim to emit JSON from GraphStore.persist by overriding Typesafe config
# Also point Typesafe to the provided external config file.
$javaOpts = "-DNGSimulator.OutputGraphRepresentation.contentType=json -Dconfig.file=$Config"
if ($Seed -ge 0) { $javaOpts = "$javaOpts -DNGSimulator.seed=$Seed" }
$env:JAVA_TOOL_OPTIONS = $javaOpts

# Build and run Main to generate a graph and persist it using current config
Write-Host "Building and running NetGameSim with config: $Config"
$proc = Start-Process -FilePath $SbtCmd -ArgumentList "clean","compile","run" -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -ne 0) { throw "sbt run failed with exit code $($proc.ExitCode)" }

# After run, identify the most recent generated file in ./output with two-line JSON
$generated = Get-ChildItem -Path .\output -Filter "NetGraph_*.ngs" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $generated) { throw "No generated NetGraph_*.ngs file found in .\output" }

# Copy/rename to requested OutPath
Copy-Item $generated.FullName $OutPath -Force
Write-Host "Exported graph JSON to $OutPath"

# Persist seed and manifest for reproducibility
$seedFile = ".\outputs\graph.seed.txt"
if ($Seed -ge 0) {
  Set-Content -Path $seedFile -Value $Seed
} else {
  # Try to read from application.conf as a fallback
  try {
    $confSeed = Select-String -Path $Config -Pattern '^\s*seed\s*=\s*([0-9]+)' | Select-Object -First 1
    if ($confSeed) {
      $val = [int]($confSeed.Matches[0].Groups[1].Value)
      Set-Content -Path $seedFile -Value $val
    }
  } catch {}
}

# Write a simple manifest with timestamp and SHA256 digest
$manifestPath = ".\outputs\graph.manifest.json"
$hash = Get-FileHash -Algorithm SHA256 -Path $OutPath | Select-Object -ExpandProperty Hash
$seedVal = if (Test-Path $seedFile) { Get-Content $seedFile -Raw } else { "" }
$now = Get-Date -Format o
$manifest = @{
  graph_path = $OutPath
  created = $now
  seed = $seedVal
  sha256 = $hash
}
$manifest | ConvertTo-Json | Set-Content -Path $manifestPath
Write-Host "Wrote seed ($seedVal) and manifest to outputs/."
