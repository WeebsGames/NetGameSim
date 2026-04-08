#!/usr/bin/env bash
set -euo pipefail

out_dir="outputs"
mkdir -p "$out_dir"

{
  echo "[mpi_check] date: $(date -Is)"
  echo "[mpi_check] which mpicxx: $(command -v mpicxx || echo 'not found')"
  echo "[mpi_check] which mpirun: $(command -v mpirun || echo 'not found')"
  echo "[mpi_check] mpicxx --version:"; (mpicxx --version || true)
  echo "[mpi_check] mpirun --version:"; (mpirun --version || true)
} | tee "$out_dir/check_mpi.txt"

echo "Wrote $out_dir/check_mpi.txt"
