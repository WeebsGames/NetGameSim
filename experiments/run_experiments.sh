#!/usr/bin/env bash
# Run a small set of experiments and archive summaries
# - Seed variation: seeds 556 and 762
# - Size variation: configs/small.conf vs configs/medium.conf
# Usage: bash experiments/run_experiments.sh [--ranks N]

# Strict mode (portable)
set -eu
if (set -o pipefail) 2>/dev/null; then :; fi

# Resolve repository root relative to this script so it can run from any CWD
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

RANKS="10"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ranks)
      RANKS="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 [--ranks N]"; exit 0;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

mkdir -p "${ROOT_DIR}/outputs/experiments"

# 1) Seed variation
for SEED in 556 762; do
  echo "[run_experiments] Running seed=$SEED ranks=$RANKS"
  bash "${ROOT_DIR}/experiments/e2e.sh" --seed "$SEED" --ranks "$RANKS"
  # rename/copy with tag (e2e also does this but we ensure presence)
  for ALG in leader dijkstra; do
    SRC="${ROOT_DIR}/outputs/summary_${ALG}.json"
    DST="${ROOT_DIR}/outputs/experiments/summary_${ALG}_seed${SEED}.json"
    if [[ -f "$SRC" ]]; then cp -f "$SRC" "$DST"; fi
  done
done

# 2) Size variation using provided configs (small and medium)
for CFG in small medium; do
  CONF_PATH="${ROOT_DIR}/configs/${CFG}.conf"
  if [[ ! -f "$CONF_PATH" ]]; then
    echo "[run_experiments] WARNING: missing $CONF_PATH; skipping $CFG" >&2
    continue
  fi
  echo "[run_experiments] Running config=$CFG ranks=$RANKS"
  bash "${ROOT_DIR}/experiments/e2e.sh" --config "$CONF_PATH" --ranks "$RANKS"
  for ALG in leader dijkstra; do
    SRC="${ROOT_DIR}/outputs/summary_${ALG}.json"
    DST="${ROOT_DIR}/outputs/experiments/summary_${ALG}_${CFG}.json"
    if [[ -f "$SRC" ]]; then cp -f "$SRC" "$DST"; fi
  done
done

echo "[run_experiments] All experiments attempted. See outputs/experiments for archived summaries."