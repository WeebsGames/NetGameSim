#!/usr/bin/env bash
set -euo pipefail

CONFIG="./GenericSimUtilities/src/main/resources/application.conf"
OUT_PATH="./outputs/graph.json"
SBT_CMD="sbt"

# Parse args: -c/--config, -o/--out, --sbt
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      CONFIG="$2"; shift 2;;
    -o|--out)
      OUT_PATH="$2"; shift 2;;
    --sbt)
      SBT_CMD="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 [-c|--config <file>] [-o|--out <file>] [--sbt <cmd>]"; exit 0;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

# Ensure output dir
out_dir=$(dirname "$OUT_PATH")
mkdir -p "$out_dir"

# Force JSON export from GraphStore.persist via Typesafe override
export JAVA_TOOL_OPTIONS="-DNGSimulator.OutputGraphRepresentation.contentType=json"

echo "[graph_export] Building and running NetGameSim with config: $CONFIG"
"$SBT_CMD" clean compile run

# Copy latest generated JSON (NetGraph_*.ngs used for JSON two-line format)
latest=$(ls -t ./output/NetGraph_*.ngs 2>/dev/null | head -n1 || true)
if [[ -z "${latest}" ]]; then
  echo "No generated NetGraph_*.ngs found in ./output" >&2
  exit 1
fi
cp -f "$latest" "$OUT_PATH"
echo "[graph_export] Exported graph JSON to $OUT_PATH"
