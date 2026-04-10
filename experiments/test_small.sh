#!/usr/bin/env bash
set -euo pipefail

# Resolve repository root relative to this script so it can run from any CWD
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Paths and defaults
RANKS=4
GRAPH_OUT="${ROOT_DIR}/outputs/graph.json"
PART_OUT="${ROOT_DIR}/outputs/part.json"
# Use a WSL/Git-Bash specific build directory to avoid CMake cache conflicts with Windows builds
BUILD_DIR="${ROOT_DIR}/build_wsl"
TINY_TWO="${ROOT_DIR}/tools/partition/testdata/tiny_graph.twojson"
TINY_ONE="${ROOT_DIR}/tools/partition/testdata/tiny_graph.json"
PARTITION="${ROOT_DIR}/tools/partition/run.py"
VALIDATE="${ROOT_DIR}/tools/partition/validate.py"

mkdir -p "${ROOT_DIR}/outputs" "${ROOT_DIR}/outputs/tests"
LOGFILE="${ROOT_DIR}/outputs/tests/test_small.log"
: > "$LOGFILE"

# 1) Prepare tiny two-line JSON graph
cp -f "$TINY_TWO" "$GRAPH_OUT"
echo "[test_small] Copied tiny graph (twojson) to $GRAPH_OUT" | tee -a "$LOGFILE"

# 2) Partition for RANKS=4
python3 "$PARTITION" "$GRAPH_OUT" --ranks "$RANKS" --out "$PART_OUT"
python3 "$VALIDATE" "$PART_OUT"

# 3) Build runtime (use separate WSL build dir and clean conflicting CMake cache if present)
if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
  # If the cache points to a Windows path or different source dir, remove it to avoid mismatch errors
  if grep -qiE "E:|\\\\" "$BUILD_DIR/CMakeCache.txt"; then
    echo "[test_small] Detected CMake cache from Windows build; cleaning $BUILD_DIR to avoid path mismatch" | tee -a "$LOGFILE"
    rm -rf "$BUILD_DIR"
  fi
fi
if [[ ! -d "$BUILD_DIR" ]]; then
  mkdir -p "$BUILD_DIR"
fi
cmake -S "${ROOT_DIR}/mpi_runtime" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" -j

# 4) Run leader election and validate leader==max node id
mpirun --oversubscribe -n "$RANKS" "$BUILD_DIR/ngs_mpi" \
  --graph "$GRAPH_OUT" \
  --part "$PART_OUT" \
  --algo leader \
  --rounds 50 \
  --log "${ROOT_DIR}/outputs/"

if [[ ! -f "${ROOT_DIR}/outputs/summary_leader.json" ]]; then
  echo "[test_small] ERROR: summary_leader.json not found" | tee -a "$LOGFILE"
  exit 2
fi

leader=$(grep -o '"leader"\s*:\s*[0-9]\+' "${ROOT_DIR}/outputs/summary_leader.json" | awk -F: '{print $2}' | tr -d ' ' || true)
if [[ -z "$leader" ]]; then
  echo "[test_small] ERROR: Could not parse leader id from summary_leader.json" | tee -a "$LOGFILE"
  exit 2
fi
# For tiny graph, max node id should be 5
if [[ "$leader" != "5" ]]; then
  echo "[test_small] ERROR: Expected leader 5, got $leader" | tee -a "$LOGFILE"
  exit 3
fi

echo "[test_small] Leader test passed (leader=$leader)" | tee -a "$LOGFILE"

# 5) Run Dijkstra and validate distances and histogram
mpirun --oversubscribe -n "$RANKS" "$BUILD_DIR/ngs_mpi" \
  --graph "$GRAPH_OUT" \
  --part "$PART_OUT" \
  --algo dijkstra \
  --source 0 \
  --log "${ROOT_DIR}/outputs/"

if [[ ! -f "${ROOT_DIR}/outputs/summary_dijkstra.json" ]]; then
  echo "[test_small] ERROR: summary_dijkstra.json not found" | tee -a "$LOGFILE"
  exit 4
fi

# Validate distances from source 0 on tiny graph
python3 - "$ROOT_DIR/outputs/summary_dijkstra.json" <<'PY'
import json, sys, math
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
res = data.get('result', {})
if not isinstance(res, dict):
    sys.exit("missing result in summary_dijkstra.json")
dm = res.get('dist_map', {})
exp = {"0":0.0, "1":2.0, "2":4.0, "3":1.0, "4":3.0, "5":5.0}
for k,v in exp.items():
    if k not in dm:
        sys.exit(f"missing distance for node {k}")
    dv = float(dm[k])
    if abs(dv - v) > 1e-6:
        sys.exit(f"distance mismatch for node {k}: got {dv}, expected {v}")
# ensure histogram exists
if 'distance_histogram' not in data:
    sys.exit("missing distance_histogram in summary_dijkstra.json")
print("[test_small] Dijkstra distances and histogram validated")
PY

# 6) Repeat check using single-line tiny_graph.json to exercise loader robustness
cp -f "$TINY_ONE" "$GRAPH_OUT"
echo "[test_small] Swapped to single-line tiny_graph.json" | tee -a "$LOGFILE"
python3 "$PARTITION" "$GRAPH_OUT" --ranks "$RANKS" --out "$PART_OUT"
python3 "$VALIDATE" "$PART_OUT"
mpirun --oversubscribe -n "$RANKS" "$BUILD_DIR/ngs_mpi" \
  --graph "$GRAPH_OUT" \
  --part "$PART_OUT" \
  --algo dijkstra \
  --source 0 \
  --log "${ROOT_DIR}/outputs/"
python3 - "$ROOT_DIR/outputs/summary_dijkstra.json" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
dm = data.get('result', {}).get('dist_map', {})
exp = {"0":0.0, "1":2.0, "2":4.0, "3":1.0, "4":3.0, "5":5.0}
for k,v in exp.items():
    dv = float(dm.get(k, float('inf')))
    if abs(dv - v) > 1e-6:
        sys.exit(f"single-line check: distance mismatch for node {k}: got {dv}, expected {v}")
print("[test_small] Single-line loader robustness validated")
PY

# 7) Negative test: rank mismatch should fail (partition says 4, run with 3)
set +e
mpirun --oversubscribe -n 3 "$BUILD_DIR/ngs_mpi" \
  --graph "$GRAPH_OUT" \
  --part "$PART_OUT" \
  --algo leader \
  --rounds 10 \
  --log "${ROOT_DIR}/outputs/"
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  echo "[test_small] ERROR: Expected rank mismatch to fail, but exit code was 0" | tee -a "$LOGFILE"
  exit 5
else
  echo "[test_small] Rank mismatch negative test passed (rc=$RC)" | tee -a "$LOGFILE"
fi

# 8) Negative test: malformed graph (only one array) should fail to load
BAD_GRAPH="${ROOT_DIR}/outputs/graph_bad.json"
head -n 1 "$TINY_TWO" > "$BAD_GRAPH"
set +e
mpirun --oversubscribe -n "$RANKS" "$BUILD_DIR/ngs_mpi" \
  --graph "$BAD_GRAPH" \
  --part "$PART_OUT" \
  --algo leader \
  --rounds 10 \
  --log "${ROOT_DIR}/outputs/"
RC2=$?
set -e
if [[ $RC2 -eq 0 ]]; then
  echo "[test_small] ERROR: Expected malformed graph to cause failure, but exit code was 0" | tee -a "$LOGFILE"
  exit 6
else
  echo "[test_small] Malformed-graph negative test passed (rc=$RC2)" | tee -a "$LOGFILE"
fi

echo "[test_small] ALL CHECKS PASSED" | tee -a "$LOGFILE"
