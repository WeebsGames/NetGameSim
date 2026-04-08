#!/usr/bin/env bash
set -euo pipefail

# Defaults
RANKS=${RANKS:-10}
GRAPH=${GRAPH:-./outputs/graph.json}
PART=${PART:-./outputs/part.json}
BUILD_DIR=${BUILD_DIR:-./build}
SOURCE=${SOURCE:-0}

# Build if missing
if [[ ! -x "$BUILD_DIR/ngs_mpi" ]]; then
  cmake -S mpi_runtime -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$BUILD_DIR" -j
fi

# Run distributed Dijkstra (source defaults to 0)
mpirun -n "$RANKS" "$BUILD_DIR/ngs_mpi" \
  --graph "$GRAPH" \
  --part "$PART" \
  --algo dijkstra \
  --source "$SOURCE" \
  --log outputs/
