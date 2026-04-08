#!/usr/bin/env bash
set -euo pipefail

CONFIG="./GenericSimUtilities/src/main/resources/application.conf"
OUT_PATH="./outputs/graph.json"
SBT_CMD="sbt"
SEED=""

# Parse args: -c/--config, -o/--out, --sbt, --seed
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      CONFIG="$2"; shift 2;;
    -o|--out)
      OUT_PATH="$2"; shift 2;;
    --sbt)
      SBT_CMD="$2"; shift 2;;
    --seed)
      SEED="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 [-c|--config <file>] [-o|--out <file>] [--sbt <cmd>] [--seed <int>]"; exit 0;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

# Ensure output dirs
out_dir=$(dirname "$OUT_PATH")
mkdir -p "$out_dir"
mkdir -p ./outputs

# Force JSON export from GraphStore.persist via Typesafe override; optionally set seed
JAVA_TOOL_OPTIONS="-DNGSimulator.OutputGraphRepresentation.contentType=json"
if [[ -n "${SEED}" ]]; then
  JAVA_TOOL_OPTIONS+=" -DNGSimulator.seed=${SEED}"
fi
export JAVA_TOOL_OPTIONS

echo "[graph_export] Building and running NetGameSim with config: $CONFIG (SEED=${SEED:-from-config})"
"$SBT_CMD" clean compile run

# Copy latest generated JSON (NetGraph_*.ngs used for JSON two-line format)
latest=$(ls -t ./output/NetGraph_*.ngs 2>/dev/null | head -n1 || true)
if [[ -z "${latest}" ]]; then
  echo "No generated NetGraph_*.ngs found in ./output" >&2
  exit 1
fi
cp -f "$latest" "$OUT_PATH"
echo "[graph_export] Exported graph JSON to $OUT_PATH"

# Persist seed and manifest for reproducibility
seed_file=./outputs/graph.seed.txt
if [[ -n "${SEED}" ]]; then
  echo -n "${SEED}" > "${seed_file}"
else
  # Try to read from application.conf as a fallback (simple grep for 'seed = <int>')
  conf_seed=$(grep -E "^\s*seed\s*=\s*[0-9]+" "$CONFIG" | head -n1 | sed -E 's/.*=\s*([0-9]+).*/\1/') || true
  if [[ -n "${conf_seed:-}" ]]; then
    echo -n "${conf_seed}" > "${seed_file}"
  fi
fi

manifest_path=./outputs/graph.manifest.json
# Compute SHA-256 (Linux: sha256sum; macOS: shasum -a 256)
if command -v sha256sum >/dev/null 2>&1; then
  hash=$(sha256sum "$OUT_PATH" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  hash=$(shasum -a 256 "$OUT_PATH" | awk '{print $1}')
else
  hash=""
fi
now=$(date -Iseconds)
seed_val=""
if [[ -f "${seed_file}" ]]; then seed_val=$(cat "${seed_file}"); fi
cat > "$manifest_path" <<EOF
{
  "graph_path": "${OUT_PATH}",
  "created": "${now}",
  "seed": "${seed_val}",
  "sha256": "${hash}"
}
EOF

echo "[graph_export] Wrote seed (${seed_val}) and manifest to outputs/."
