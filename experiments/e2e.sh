#!/usr/bin/env bash
# End-to-end runner: generate graph -> partition -> build -> run leader + dijkstra
# Usage examples:
#   bash experiments/e2e.sh --seed 123 --ranks 10
#   bash experiments/e2e.sh --config ./GenericSimUtilities/src/main/resources/application.conf --ranks 10

# Strict mode (portable)
set -eu
if (set -o pipefail) 2>/dev/null; then :; fi

# Resolve repository root relative to this script so it can run from any CWD
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

SEED=""
RANKS="10"
CONFIG="${ROOT_DIR}/GenericSimUtilities/src/main/resources/application.conf"
GRAPH_OUT="${ROOT_DIR}/outputs/graph.json"
PART_OUT="${ROOT_DIR}/outputs/part.json"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seed)
      SEED="$2"; shift 2;;
    --ranks)
      RANKS="$2"; shift 2;;
    --config)
      CONFIG="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 [--seed N] [--ranks N] [--config <application.conf>]"; exit 0;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

mkdir -p "${ROOT_DIR}/outputs" "${ROOT_DIR}/outputs/experiments"

# 1) Generate graph (two-array JSON)
if [[ -n "${SEED}" ]]; then
  bash "${ROOT_DIR}/tools/graph_export/run.sh" --config "$CONFIG" --out "$GRAPH_OUT" --seed "$SEED"
else
  bash "${ROOT_DIR}/tools/graph_export/run.sh" --config "$CONFIG" --out "$GRAPH_OUT"
fi

# 2) Partition using requested ranks
python3 "${ROOT_DIR}/tools/partition/run.py" "$GRAPH_OUT" --ranks "$RANKS" --out "$PART_OUT"
python3 "${ROOT_DIR}/tools/partition/validate.py" "$PART_OUT"

# 3) Run leader and dijkstra (scripts auto-match -n to partition and add --oversubscribe)
bash "${ROOT_DIR}/experiments/run_leader.sh"
bash "${ROOT_DIR}/experiments/run_dijkstra.sh"

# 4) Archive summaries with a tag
TAG="seed${SEED}"
if [[ -z "${SEED}" ]]; then TAG="untagged"; fi
cp -f "${ROOT_DIR}/outputs/summary_leader.json"    "${ROOT_DIR}/outputs/experiments/summary_leader_${TAG}.json" 2>/dev/null || true
cp -f "${ROOT_DIR}/outputs/summary_dijkstra.json"  "${ROOT_DIR}/outputs/experiments/summary_dijkstra_${TAG}.json" 2>/dev/null || true

echo "[e2e] Completed. Summaries in outputs/ and archived (if present) under outputs/experiments/."