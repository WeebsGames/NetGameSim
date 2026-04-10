#!/usr/bin/env python3
"""
Update REPORT.md experiment tables from archived summaries under outputs/experiments/.

- Fills the Seed Variation table (EXP_SEED_TABLE_*) from files named:
    outputs/experiments/summary_{leader,dijkstra}_seed<SEED>.json
- Fills the Size Variation table (EXP_SIZE_TABLE_*) from files named:
    outputs/experiments/summary_{leader,dijkstra}_{small|medium}.json
- Replaces the EXP_UPDATE_NOTE_* block with a timestamp of this update.

Usage:
  python3 experiments/update_report_from_summaries.py [--report REPORT_PATH] [--expdir EXP_DIR]
Defaults:
  REPORT_PATH = ./REPORT.md
  EXP_DIR     = ./outputs/experiments

This script is idempotent and will only modify the parts of REPORT.md between marker blocks.
"""
from __future__ import annotations
import argparse
import json
import os
import re
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

SEED_START = "<!-- EXP_SEED_TABLE_START -->"
SEED_END   = "<!-- EXP_SEED_TABLE_END -->"
SIZE_START = "<!-- EXP_SIZE_TABLE_START -->"
SIZE_END   = "<!-- EXP_SIZE_TABLE_END -->"
NOTE_START = "<!-- EXP_UPDATE_NOTE_START -->"
NOTE_END   = "<!-- EXP_UPDATE_NOTE_END -->"

Row = Tuple[str, int, str, int, int, int, int]  # (algo, ranks, tag, iterations, messages, bytes, runtime_ms)


def load_json(path: str) -> Optional[Dict]:
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return None


def gather_seed_rows(expdir: str) -> List[Row]:
    rows: List[Row] = []
    # Detect available seeds by scanning filenames summary_*_seed<val>.json
    pat = re.compile(r"^summary_(leader|dijkstra)_seed(\d+)\.json$")
    by_tag: Dict[str, Dict[str, Dict]] = {}
    for name in os.listdir(expdir) if os.path.isdir(expdir) else []:
        m = pat.match(name)
        if not m:
            continue
        algo = m.group(1)
        seed = m.group(2)
        d = load_json(os.path.join(expdir, name))
        if not d:
            continue
        by_tag.setdefault(seed, {})[algo] = d
    # Build rows sorted by seed value
    for seed in sorted(by_tag.keys(), key=lambda s: int(s)):
        for algo in ("leader", "dijkstra"):
            d = by_tag[seed].get(algo)
            if not d:
                continue
            try:
                ranks = int(d.get("ranks", 0))
                iterations = int(d.get("iterations", 0))
                messages = int(d.get("messages_sent", 0))
                bytes_sent = int(d.get("bytes_sent", 0))
                runtime_ms = int(d.get("runtime_ms", 0))
                rows.append((algo, ranks, seed, iterations, messages, bytes_sent, runtime_ms))
            except Exception:
                continue
    return rows


def gather_size_rows(expdir: str) -> List[Row]:
    rows: List[Row] = []
    pat = re.compile(r"^summary_(leader|dijkstra)_(small|medium)\.json$")
    for name in os.listdir(expdir) if os.path.isdir(expdir) else []:
        m = pat.match(name)
        if not m:
            continue
        algo = m.group(1)
        tag = m.group(2)  # small or medium
        d = load_json(os.path.join(expdir, name))
        if not d:
            continue
        try:
            ranks = int(d.get("ranks", 0))
            iterations = int(d.get("iterations", 0))
            messages = int(d.get("messages_sent", 0))
            bytes_sent = int(d.get("bytes_sent", 0))
            runtime_ms = int(d.get("runtime_ms", 0))
            rows.append((algo, ranks, tag, iterations, messages, bytes_sent, runtime_ms))
        except Exception:
            continue
    # Order: leader small, dijkstra small, leader medium, dijkstra medium
    order_key = {"leader": 0, "dijkstra": 1, "small": 0, "medium": 1}
    rows.sort(key=lambda r: (order_key.get(r[2], 99), order_key.get(r[0], 99)))
    return rows


def make_seed_table(rows: List[Row]) -> str:
    # Header
    lines = [
        "| algo | ranks | seed | iterations | messages_sent | bytes_sent | runtime_ms |",
        "|------|-------|------|------------|---------------|------------|------------|",
    ]
    for algo, ranks, seed, iters, msgs, by, rt in rows:
        lines.append(f"| {algo} | {ranks} | {seed} | {iters} | {msgs} | {by} | {rt} |")
    return "\n".join(lines)


def make_size_table(rows: List[Row]) -> str:
    lines = [
        "| algo | ranks | config | iterations | messages_sent | bytes_sent | runtime_ms |",
        "|------|-------|--------|------------|---------------|------------|------------|",
    ]
    for algo, ranks, cfg, iters, msgs, by, rt in rows:
        lines.append(f"| {algo} | {ranks} | {cfg}  | {iters} | {msgs} | {by} | {rt} |")
    return "\n".join(lines)


def replace_block(text: str, start: str, end: str, payload: str) -> str:
    s = text.find(start)
    e = text.find(end)
    if s == -1 or e == -1 or e < s:
        return text  # markers missing; do not modify
    s_after = s + len(start)
    return text[:s_after] + "\n" + payload + "\n" + text[e:]


def update_report(report_path: str, expdir: str) -> bool:
    try:
        with open(report_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"[update_report] REPORT not found: {report_path}")
        return False

    seed_rows = gather_seed_rows(expdir)
    size_rows = gather_size_rows(expdir)

    changed = False

    if seed_rows:
        seed_table = make_seed_table(seed_rows)
        new_content = replace_block(content, SEED_START, SEED_END, seed_table)
        if new_content != content:
            content = new_content
            changed = True
    else:
        print("[update_report] No seed-based summaries found; leaving seed table unchanged.")

    if size_rows:
        size_table = make_size_table(size_rows)
        new_content = replace_block(content, SIZE_START, SIZE_END, size_table)
        if new_content != content:
            content = new_content
            changed = True
    else:
        print("[update_report] No size-based summaries found; leaving size table unchanged.")

    # Update note block with timestamp
    ts = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    note = f"Last updated automatically at {ts}"
    new_content = replace_block(content, NOTE_START, NOTE_END, note)
    if new_content != content:
        content = new_content
        changed = True

    if changed:
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"[update_report] Updated {report_path} from summaries under {expdir}.")
    else:
        print("[update_report] No changes made (tables may already be up-to-date or markers missing).")
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", default=os.path.join(".", "REPORT.md"))
    ap.add_argument("--expdir", default=os.path.join(".", "outputs", "experiments"))
    args = ap.parse_args()
    update_report(args.report, args.expdir)


if __name__ == "__main__":
    main()
