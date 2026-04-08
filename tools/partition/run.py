#!/usr/bin/env python3
import json
import argparse
import datetime
from collections import defaultdict


def contiguous_owner(node_id: int, total_nodes: int, ranks: int) -> int:
    # Assign nodes to ranks by contiguous ranges of ids
    # Example: with 10 nodes and 3 ranks -> [0..3]->0, [4..6]->1, [7..9]->2
    # We use integer division with ceiling for block size
    import math
    block = math.ceil(total_nodes / ranks)
    return min(node_id // block, ranks - 1)


def main():
    p = argparse.ArgumentParser(description="Partition graph nodes across MPI ranks")
    p.add_argument("graph", help="Path to graph JSON (two-line JSON: nodes then edges)")
    p.add_argument("--ranks", type=int, required=True, help="Number of MPI ranks")
    p.add_argument("--out", required=True, help="Output partition JSON path")
    args = p.parse_args()

    with open(args.graph, "r", encoding="utf-8") as f:
        nodes_line = f.readline()
        edges_line = f.readline()
    nodes = json.loads(nodes_line)
    edges = json.loads(edges_line)

    # Extract node ids and sort
    try:
        node_ids = sorted(int(n["id"]) for n in nodes)
    except Exception as e:
        raise RuntimeError("Nodes JSON must contain objects with an 'id' field") from e

    n_total = len(node_ids)
    if args.ranks < 1:
        raise SystemExit("--ranks must be >= 1")
    if n_total == 0:
        raise SystemExit("Graph contains no nodes")

    owners = {}
    per_rank_nodes = defaultdict(list)
    for nid in node_ids:
        r = contiguous_owner(nid, total_nodes=n_total, ranks=args.ranks)
        owners[str(nid)] = r
        per_rank_nodes[r].append(nid)

    # Ghost nodes: remote neighbors referenced by edges
    ghosts = defaultdict(set)
    cross_edges = 0
    for e in edges:
        try:
            u = int(e["fromNode"]["id"]) if isinstance(e.get("fromNode"), dict) else int(e.get("from", e.get("u")))
            v = int(e["toNode"]["id"]) if isinstance(e.get("toNode"), dict) else int(e.get("to", e.get("v")))
        except Exception as ex:
            raise RuntimeError("Edge JSON must contain fromNode.id and toNode.id (or from/to)") from ex
        ru = owners[str(u)]
        rv = owners[str(v)]
        if ru != rv:
            cross_edges += 1
            ghosts[ru].add(v)
            ghosts[rv].add(u)

    out = {
        "meta": {
            "created": datetime.datetime.utcnow().isoformat() + "Z",
            "method": "contiguous_by_id",
            "ranks": args.ranks,
            "nodes": n_total,
            "cross_edges": cross_edges,
        },
        "owners": owners,
        "per_rank": {
            str(r): {
                "nodes": per_rank_nodes[r],
                "ghosts": sorted(list(ghosts[r]))
            } for r in range(args.ranks)
        }
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)

    print(f"Wrote partition to {args.out}: ranks={args.ranks}, nodes={n_total}, cross_edges={cross_edges}")


if __name__ == "__main__":
    main()
