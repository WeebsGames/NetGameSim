#!/usr/bin/env bash
# Strict mode (portable): enable -e and -u everywhere; add pipefail only if supported
set -eu
if (set -o pipefail) 2>/dev/null; then :; fi

# Resolve repository root relative to this script so it can run from any CWD
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Detect WSL (to avoid CMake cache conflicts with Windows builds)
IS_WSL=0
if [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version; then
  IS_WSL=1
fi

# Defaults (override via env vars if desired)
RANKS=${RANKS:-10}
GRAPH=${GRAPH:-"${ROOT_DIR}/outputs/graph.json"}
PART=${PART:-"${ROOT_DIR}/outputs/part.json"}
if [[ ${IS_WSL} -eq 1 ]]; then
  BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build_wsl"}
else
  BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
fi
SOURCE=${SOURCE:-0}

# If a partition file exists, prefer its meta.ranks unless OVERRIDE_RANKS=1 is set
if [[ -f "$PART" ]]; then
  PART_RANKS=$(python3 - "$PART" <<'PY'
import json,sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        d = json.load(f)
    print(int(d.get('meta', {}).get('ranks', 0)))
except Exception:
    print(0)
PY
  )
  if [[ "${OVERRIDE_RANKS:-0}" -ne 1 && "${PART_RANKS}" -gt 0 ]]; then
    RANKS="${PART_RANKS}"
  fi
fi

# Clean incompatible CMake cache if present (e.g., created on Windows paths)
if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
  if grep -qiE "E:|[A-Za-z]:\\\\|NetGameSim\\\\mpi_runtime" "$BUILD_DIR/CMakeCache.txt" || \
     ! grep -q "CMAKE_HOME_DIRECTORY:INTERNAL=${ROOT_DIR}/mpi_runtime" "$BUILD_DIR/CMakeCache.txt" 2>/dev/null; then
    echo "[run_dijkstra] Cleaning incompatible CMake cache at $BUILD_DIR"
    rm -rf "$BUILD_DIR"
  fi
fi

# Build if missing
if [[ ! -x "$BUILD_DIR/ngs_mpi" ]]; then
  cmake -S "${ROOT_DIR}/mpi_runtime" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$BUILD_DIR" -j
fi

# Run distributed Dijkstra (source defaults to 0)
mpirun --oversubscribe -n "$RANKS" "$BUILD_DIR/ngs_mpi" \
  --graph "$GRAPH" \
  --part "$PART" \
  --algo dijkstra \
  --source "$SOURCE" \
  --log "${ROOT_DIR}/outputs/" 
