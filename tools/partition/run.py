#!/usr/bin/env python3
import json
import argparse
import datetime
from collections import defaultdict
from typing import Tuple


def contiguous_owner(node_id: int, total_nodes: int, ranks: int) -> int:
    # Assign nodes to ranks by contiguous ranges of ids
    # Example: with 10 nodes and 3 ranks -> [0..3]->0, [4..6]->1, [7..9]->2
    # We use integer division with ceiling for block size
    import math
    block = math.ceil(total_nodes / ranks)
    return min(node_id // block, ranks - 1)


def _parse_two_arrays(text: str) -> Tuple[list, list]:
    """
    Parse a file that contains exactly two top-level JSON arrays back-to-back
    (optionally with whitespace/newlines between/around them). Works for both
    single-line and pretty-printed multi-line inputs.
    """
    # Strip UTF-8 BOM if present
    if text and text[0] == "\ufeff":
        text = text.lstrip("\ufeff")
    dec = json.JSONDecoder()
    i = 0
    n = len(text)
    # skip leading whitespace
    while i < n and text[i].isspace():
        i += 1
    if i >= n:
        raise SystemExit("Graph JSON is empty; expected two arrays: nodes then edges")
    arr1, idx1 = dec.raw_decode(text, i)
    i = idx1
    # skip whitespace between arrays
    while i < n and text[i].isspace():
        i += 1
    if i >= n:
        raise SystemExit("Graph JSON contains only one JSON value; expected two arrays (nodes then edges)")
    arr2, idx2 = dec.raw_decode(text, i)
    # Optional trailing whitespace allowed
    return arr1, arr2


def main():
    p = argparse.ArgumentParser(description="Partition graph nodes across MPI ranks")
    p.add_argument("graph", help="Path to graph JSON (two arrays: nodes then edges; multi-line OK)")
    p.add_argument("--ranks", type=int, required=True, help="Number of MPI ranks")
    p.add_argument("--out", required=True, help="Output partition JSON path")
    args = p.parse_args()

    # Read entire file to support pretty-printed multi-line arrays
    with open(args.graph, "r", encoding="utf-8") as f:
        text = f.read()

    try:
        nodes, edges = _parse_two_arrays(text)
    except json.JSONDecodeError as jde:
        raise SystemExit(f"Failed to parse graph JSON: {jde}")

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
            "created": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
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
