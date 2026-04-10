#!/usr/bin/env bash
# Run two experiments: (A) seed variation; (B) size variation (small vs medium)
# Usage: bash experiments/run_experiments.sh [--ranks R]
# Results: copies summaries into outputs/experiments/ with descriptive filenames

set -eu
if (set -o pipefail) 2>/dev/null; then :; fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
OUT_DIR="${ROOT_DIR}/outputs"
EXP_DIR="${OUT_DIR}/experiments"
mkdir -p "$EXP_DIR"

RANKS=10
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ranks) RANKS="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 [--ranks R]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

run_and_archive() {
  local tag="$1" # e.g., seed556 or small or medium
  local s_leader="${OUT_DIR}/summary_leader.json"
  local s_dijk="${OUT_DIR}/summary_dijkstra.json"
  # Copy with tag
  cp -f "$s_leader" "${EXP_DIR}/summary_leader_${tag}.json"
  cp -f "$s_dijk" "${EXP_DIR}/summary_dijkstra_${tag}.json"
}

# Experiment A: seed variation (556 and 762)
echo "[run_experiments] Seed variation @ ranks=${RANKS}: seeds 556 and 762"
bash "${ROOT_DIR}/experiments/e2e.sh" --seed 556 --ranks "$RANKS"
run_and_archive "seed556"

bash "${ROOT_DIR}/experiments/e2e.sh" --seed 762 --ranks "$RANKS"
run_and_archive "seed762"

echo "[run_experiments] Size variation @ ranks=${RANKS}: small vs medium configs"
# Experiment B: size variation using provided configs
bash "${ROOT_DIR}/experiments/e2e.sh" --ranks "$RANKS" --config "${ROOT_DIR}/configs/small.conf"
run_and_archive "small"

bash "${ROOT_DIR}/experiments/e2e.sh" --ranks "$RANKS" --config "${ROOT_DIR}/configs/medium.conf"
run_and_archive "medium"

echo "[run_experiments] Done. See ${EXP_DIR}/ for archived summaries."
