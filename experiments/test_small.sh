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
TINY="${ROOT_DIR}/tools/partition/testdata/tiny_graph.twojson"
PARTITION="${ROOT_DIR}/tools/partition/run.py"
VALIDATE="${ROOT_DIR}/tools/partition/validate.py"

mkdir -p "${ROOT_DIR}/outputs" "${ROOT_DIR}/outputs/tests"

# 1) Prepare tiny two-line JSON graph
cp -f "$TINY" "$GRAPH_OUT"
echo "[test_small] Copied tiny graph to $GRAPH_OUT"

# 2) Partition for RANKS=4
python3 "$PARTITION" "$GRAPH_OUT" --ranks "$RANKS" --out "$PART_OUT"
python3 "$VALIDATE" "$PART_OUT"

# 3) Build runtime (use separate WSL build dir and clean conflicting CMake cache if present)
if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
  # If the cache points to a Windows path or different source dir, remove it to avoid mismatch errors
  if grep -qiE "E:|\\\\" "$BUILD_DIR/CMakeCache.txt"; then
    echo "[test_small] Detected CMake cache from Windows build; cleaning $BUILD_DIR to avoid path mismatch"
    rm -rf "$BUILD_DIR"
  fi
fi
if [[ ! -d "$BUILD_DIR" ]]; then
  mkdir -p "$BUILD_DIR"
fi
cmake -S "${ROOT_DIR}/mpi_runtime" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" -j

# 4) Run leader election and validate leader==max node id
mpirun -n "$RANKS" "$BUILD_DIR/ngs_mpi" \
  --graph "$GRAPH_OUT" \
  --part "$PART_OUT" \
  --algo leader \
  --rounds 50 \
  --log "${ROOT_DIR}/outputs/"

if [[ ! -f "${ROOT_DIR}/outputs/summary_leader.json" ]]; then
  echo "[test_small] ERROR: summary_leader.json not found" | tee "${ROOT_DIR}/outputs/tests/test_small.log"
  exit 2
fi

leader=$(grep -o '"leader"\s*:\s*[0-9]\+' "${ROOT_DIR}/outputs/summary_leader.json" | awk -F: '{print $2}' | tr -d ' ' || true)
if [[ -z "$leader" ]]; then
  echo "[test_small] ERROR: Could not parse leader id from summary_leader.json" | tee -a "${ROOT_DIR}/outputs/tests/test_small.log"
  exit 2
fi
# For tiny graph, max node id should be 5
if [[ "$leader" != "5" ]]; then
  echo "[test_small] ERROR: Expected leader 5, got $leader" | tee -a "${ROOT_DIR}/outputs/tests/test_small.log"
  exit 3
fi

echo "[test_small] Leader test passed (leader=$leader)" | tee -a "${ROOT_DIR}/outputs/tests/test_small.log"

# 5) Run Dijkstra (placeholder until algorithm is complete). Just ensure it runs and writes a summary.
mpirun -n "$RANKS" "$BUILD_DIR/ngs_mpi" \
  --graph "$GRAPH_OUT" \
  --part "$PART_OUT" \
  --algo dijkstra \
  --source 0 \
  --log "${ROOT_DIR}/outputs/"

if [[ ! -f "${ROOT_DIR}/outputs/summary_dijkstra.json" ]]; then
  echo "[test_small] ERROR: summary_dijkstra.json not found" | tee -a "${ROOT_DIR}/outputs/tests/test_small.log"
  exit 4
fi

echo "[test_small] Dijkstra placeholder run completed; summary present." | tee -a "${ROOT_DIR}/outputs/tests/test_small.log"

echo "[test_small] ALL CHECKS PASSED" | tee -a "${ROOT_DIR}/outputs/tests/test_small.log"
