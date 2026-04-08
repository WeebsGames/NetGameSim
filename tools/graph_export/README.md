# Graph Export Tool

This tool invokes NetGameSim to generate a connected graph and exports it to a portable JSON format consumable by the partitioner and MPI runtime.

Output format: two JSON lines in a single file
- Line 1: array of node objects as produced by NetGameSim
- Line 2: array of edge objects (actions) including `fromNode`, `toNode`, and `cost`

Usage (PowerShell on Windows):

```
# Generate a graph to outputs/graph.json using the config seed and ensure JSON export
./tools/graph_export/run.ps1 -Config .\GenericSimUtilities\src\main\resources\application.conf -OutPath .\outputs\graph.json
```

Notes
- The tool sets the Typesafe Config override `NGSimulator.OutputGraphRepresentation.contentType=json` so NetGameSim writes JSON instead of `.ngs`.
- The base output directory is already configured to `./output` for native `.ngs` outputs; JSON will be written to the path passed to the script.
