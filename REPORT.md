# Project Report: NetGameSim → MPI Distributed Algorithms

This report summarizes the design, implementation, and results for running distributed algorithms (Leader Election and Dijkstra Shortest Paths) on graphs generated via NetGameSim and partitioned across MPI ranks.

## 1. Overview
- Graph generation: NetGameSim (Scala) exports a portable two‑array JSON file: line 1 = nodes; line 2 = edges with positive weights.
- Partitioning: Python tool assigns each node to exactly one rank (contiguous id ranges), emits owner map and per‑rank node/ghost lists.
- MPI runtime: C++17 + OpenMPI (via WSL on Windows). Implements:
  - Leader Election baseline (global max id agreement via MPI_Allreduce)
  - Distributed Dijkstra baseline (global-min selection per iteration) with per‑rank logging and metrics.
- Reproducibility: Seeds recorded in outputs/graph.manifest.json; runtime writes outputs/run_manifest.json. Summaries include seed and arguments.

## 2. Data formats
- Graph (two JSON arrays in one file):
  - nodes: [{"id": 0}, {"id": 1}, ...]
  - edges: [{"from": 0, "to": 1, "cost": 2.0}, ...] or NetGameSim edge objects with fromNode/toNode.id.
- Partition JSON:
  - meta: {ranks, nodes, cross_edges, created}
  - owners: {"<node_id>": <rank>}
  - per_rank: {"<rank>": {nodes: [...], ghosts: [...]}}

## 3. Algorithms and messaging
- Leader Election (baseline): reduce global max node id; verify agreement. Metrics: 1 iteration, small message/byte counts.
- Distributed Dijkstra (baseline):
  - Local PQ per rank of unsettled owned nodes.
  - Each iteration gathers best local candidates to rank 0, selects global minimum, broadcasts selected node to all ranks.
  - Owning rank relaxes outgoing edges; distance updates broadcast to all ranks (batched per step in current baseline).
  - Termination when no candidates remain (global selection returns none). Distances gathered via MPI_Allreduce(MPI_MIN).
  - Metrics: iterations, messages_sent, bytes_sent, runtime_ms. Rank 0 also emits a fixed‑width 10‑bin distance_histogram over finite distances.

## 4. Logging, metrics, and outputs
- Per‑rank logs: outputs/logs/<algo>_rank<r>.log
- Per‑algorithm summaries: outputs/summary_leader.json, outputs/summary_dijkstra.json
- Run manifest per execution: outputs/run_manifest.json

## 5. How to reproduce (quick)
- WSL/Linux/macOS:
```
bash tools/graph_export/run.sh --out ./outputs/graph.json --seed 123
python3 tools/partition/run.py ./outputs/graph.json --ranks 10 --out ./outputs/part.json
bash experiments/run_leader.sh
bash experiments/run_dijkstra.sh
```
- Windows PowerShell:
```
./tools/graph_export/run.ps1 -OutPath .\outputs\graph.json -Seed 123
py tools/partition/run.py .\outputs\graph.json --ranks 10 --out .\outputs\part.json
./experiments/run_leader.ps1
./experiments/run_dijkstra.ps1
```
- One‑command pipeline via sbt:
```
sbt mpiE2E
```

## 6. Tests and validation
- Tiny deterministic graph fixture validates:
  - Leader agreement (leader == max node id)
  - Dijkstra correctness from source 0 (checks exact distances)
  - Loader robustness (pretty‑printed vs single‑line two‑array JSON)
  - Negative cases: rank mismatch and malformed input
- Run:
```
bash experiments/test_small.sh
./experiments/test_small.ps1
```

## 7. Experiments (to be filled after runs)
- Experiment A (seed variation @ 10 ranks):
  - Seed S1 vs Seed S2; compare iterations, messages_sent, bytes_sent, runtime_ms
- Experiment B (size variation @ 10 ranks):
  - small.conf vs medium.conf graphs; compare metrics and discuss trends

Record results by running experiments/e2e.sh (or sbt mpiE2E) for each configuration and collecting summary JSONs under outputs/.

## 8. Assumptions and limitations
- Graph must be connected and edge weights nonnegative (Dijkstra requirement). Upstream NetGameSim can generate unconnected graphs; ensure configuration produces connected graphs (e.g., sufficient edgeProbability and connectedness).
- Current Dijkstra baseline uses global collectives per iteration and broadcast updates; scalable enough for coursework but not fully decentralized.
- Partitioning strategy: contiguous by id; not cut‑aware. Ghost sets reflect cross edges.

## 9. Future work
- Implement synchronous FloodMax leader election with round‑based boundary exchanges and Allreduce convergence.
- Add cut‑aware partitioning and compare message counts vs contiguous by id.
- Add asynchronous relaxation or delta‑stepping variant and compare against the baseline.

## 10. Environment
- C++17, OpenMPI (WSL Ubuntu recommended), CMake/g++.
- Scala/JDK + sbt to run NetGameSim.



## Experiments

This section documents how to reproduce the two required experiments and serves as a placeholder to paste metrics produced on your machine. All commands assume you are in the repository root.

Artifacts written by the runtime and scripts:
- Per‑rank logs: outputs/logs/<algo>_rank<r>.log
- Per‑algorithm summaries (rank 0): outputs/summary_leader.json, outputs/summary_dijkstra.json
- Distance histogram (Dijkstra only): present under the key distance_histogram in outputs/summary_dijkstra.json
- Run manifest: outputs/run_manifest.json (algo, args, seed, input file sizes, timestamps)
- Archived summaries for experiments: outputs/experiments/*.json

### How to run the experiment suite (default ranks = 10)
- WSL/Linux/macOS:
  - bash experiments/run_experiments.sh --ranks 10
- Windows PowerShell (run each e2e step and pass Seed):
  - ./experiments/e2e.ps1 -Ranks 10 -Seed 556
  - ./experiments/e2e.ps1 -Ranks 10 -Seed 762
  - ./experiments/e2e.ps1 -Ranks 10 -Config .\configs\small.conf
  - ./experiments/e2e.ps1 -Ranks 10 -Config .\configs\medium.conf

The above creates/updates the following archived summaries:
- outputs/experiments/summary_{leader,dijkstra}_seed556.json
- outputs/experiments/summary_{leader,dijkstra}_seed762.json
- outputs/experiments/summary_{leader,dijkstra}_small.json
- outputs/experiments/summary_{leader,dijkstra}_medium.json

### Experiment A — Seed variation (seed 556 vs 762)
Paste the key metrics below after running the suite (all values from rank‑0 summaries):

| algo | ranks | seed | iterations | messages_sent | bytes_sent | runtime_ms |
|------|-------|------|------------|---------------|------------|------------|
| leader | 10 | 556 |            |               |            |            |
| dijkstra | 10 | 556 |            |               |            |            |
| leader | 10 | 762 |            |               |            |            |
| dijkstra | 10 | 762 |            |               |            |            |

Notes/observations:
- Briefly compare iterations/messages/runtime across seeds. Mention any notable histogram shape differences for Dijkstra.

### Experiment B — Size variation (small vs medium)
Run with configs/small.conf and configs/medium.conf at ranks=10. Paste metrics below:

| algo | ranks | config | iterations | messages_sent | bytes_sent | runtime_ms |
|------|-------|--------|------------|---------------|------------|------------|
| leader | 10 | small  |            |               |            |            |
| dijkstra | 10 | small  |            |               |            |            |
| leader | 10 | medium |            |               |            |            |
| dijkstra | 10 | medium |            |               |            |            |

Notes/observations:
- Comment on trends as the graph grows (e.g., more iterations/messages for Dijkstra, runtime impacts). Optionally reference distance_histogram changes.

### Assumptions and validation
- Graphs are connected and edges have nonnegative weights (required for Dijkstra correctness).
- Partition meta.ranks must match MPI world size; scripts auto‑sync ranks to partition to avoid mismatches.
- tests: See experiments/test_small.sh|.ps1 — they validate leader agreement, Dijkstra distances for a tiny deterministic graph, presence of distance_histogram, and include negative tests (rank mismatch, malformed input).
