#!/usr/bin/env python3
import json
import sys
from typing import Dict, Set


def fail(msg: str) -> int:
    print(f"[partition:validate] ERROR: {msg}")
    return 2


def ok(msg: str) -> int:
    print(f"[partition:validate] OK: {msg}")
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: validate.py <partition.json>")
        return 1
    ppath = sys.argv[1]
    try:
        with open(ppath, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as ex:
        return fail(f"Cannot read JSON: {ex}")

    # Basic shape
    if not isinstance(data, dict):
        return fail("Top-level JSON must be an object")
    meta = data.get("meta", {})
    owners = data.get("owners", {})
    per_rank = data.get("per_rank", {})
    if not isinstance(owners, dict):
        return fail("'owners' must be an object map of node_id -> rank")
    if not isinstance(per_rank, dict):
        return fail("'per_rank' must be an object of rank -> {nodes, ghosts}")
    ranks = int(meta.get("ranks", 0))
    nodes_total = int(meta.get("nodes", 0))
    if ranks < 1:
        return fail("meta.ranks must be >= 1")
    if nodes_total < 1:
        return fail("meta.nodes must be >= 1")

    # Every node must have exactly one owner
    if len(owners) != nodes_total:
        return fail(f"owners count {len(owners)} does not match meta.nodes {nodes_total}")
    seen_nodes: Set[int] = set()
    for k, v in owners.items():
        try:
            nid = int(k)
            rk = int(v)
        except Exception:
            return fail("owners keys must be node ids (int as string) and values ranks (int)")
        if nid in seen_nodes:
            return fail(f"duplicate owner for node {nid}")
        seen_nodes.add(nid)
        if rk < 0 or rk >= ranks:
            return fail(f"owner rank {rk} out of range for node {nid}")

    # per_rank consistency: nodes listed there should match owners map
    for rk_str, ent in per_rank.items():
        try:
            rk = int(rk_str)
        except Exception:
            return fail(f"per_rank key '{rk_str}' must be an int rank")
        if rk < 0 or rk >= ranks:
            return fail(f"per_rank rank {rk} out of range")
        nodes = ent.get("nodes", []) or []
        for nid in nodes:
            if str(nid) not in owners:
                return fail(f"per_rank nodes contains unknown node id {nid}")
            if int(owners[str(nid)]) != rk:
                return fail(f"per_rank nodes mismatch: node {nid} listed under rank {rk} but owners says {owners[str(nid)]}")

    print("[partition:validate] Partition JSON looks consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
