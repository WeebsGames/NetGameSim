#!/usr/bin/env bash
# End-to-end runner: generate graph -> partition -> build -> run leader & dijkstra
# Usage:
#   bash experiments/e2e.sh [--seed N] [--ranks R] [--config <path>]
# Notes:
# - Uses tools/graph_export/run.sh (sbt) to generate two-array JSON graph.
# - Uses tools/partition/run.py to create outputs/part.json.
# - Uses experiments/run_leader.sh and run_dijkstra.sh which auto-sync -n to partition and add --oversubscribe.

set -eu
if (set -o pipefail) 2>/dev/null; then :; fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

SEED=""
RANKS=10
CONFIG="${ROOT_DIR}/GenericSimUtilities/src/main/resources/application.conf"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seed) SEED="$2"; shift 2;;
    --ranks) RANKS="$2"; shift 2;;
    --config) CONFIG="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 [--seed N] [--ranks R] [--config <path>]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

OUT_DIR="${ROOT_DIR}/outputs"
mkdir -p "$OUT_DIR"

# 1) Graph export
if [[ -n "$SEED" ]]; then
  echo "[e2e] Exporting graph with seed=$SEED"
  bash "${ROOT_DIR}/tools/graph_export/run.sh" --config "$CONFIG" --out "${OUT_DIR}/graph.json" --seed "$SEED"
else
  echo "[e2e] Exporting graph (seed from config)"
  bash "${ROOT_DIR}/tools/graph_export/run.sh" --config "$CONFIG" --out "${OUT_DIR}/graph.json"
fi

# 2) Partition
echo "[e2e] Partitioning graph with ranks=$RANKS"
python3 "${ROOT_DIR}/tools/partition/run.py" "${OUT_DIR}/graph.json" --ranks "$RANKS" --out "${OUT_DIR}/part.json"
python3 "${ROOT_DIR}/tools/partition/validate.py" "${OUT_DIR}/part.json"

# 3) Run leader and dijkstra (scripts will build if needed and auto-match -n to partition)
 echo "[e2e] Running leader election"
bash "${ROOT_DIR}/experiments/run_leader.sh"

echo "[e2e] Running Dijkstra (source=0)"
bash "${ROOT_DIR}/experiments/run_dijkstra.sh"

echo "[e2e] Complete. Summaries in outputs/: summary_leader.json, summary_dijkstra.json"
