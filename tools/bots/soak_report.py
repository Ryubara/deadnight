"""The bot soak and the parity batch (bots plan, phase 7): runs whole nights of hosted bots in the real
server, sets each cell beside the balance simulator's matching cell and writes the report.

    uv run python tools/bots/soak_report.py run   --out <folder> [--nights 100] [--jobs 3] [--chunk 5]
    uv run python tools/bots/soak_report.py merge --out <folder> [--gate]

`run` plays the cells in chunks (one Godot process of `--chunk` nights each; a chunk that is already in
`<folder>/chunks` is skipped, so a stopped run goes on where it stopped) and `merge` reads every chunk
into `report.json` and `report.md`. The nightly workflow runs `run` for one chunk per job and `merge`
once at the end (`.github/workflows/bots-nightly.yml`). The cells:

* the parity batch: each bot profile (rookie, regular, veteran) beside the simulator's skill (weak,
  average, strong), for 1, 2 and 4 bots alone in the lot, Roam, which is what a room with no person is;
* the order soaks: a person stand-in (the old autopilot) and three bots of the regular profile, under
  each standing order (roam, follow, hold), for the gates of `docs/research/bots.md`.

Needs the pinned Godot from the GDStudio kit (`gds tool path godot`).
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

GAME = Path(__file__).resolve().parents[2] / "game"
PROFILES = {"rookie": "weak", "regular": "average", "veteran": "strong"}
TEAM_SIZES = [1, 2, 4]
ORDERS = ["roam", "follow", "hold"]
SCENE = "res://tests/captures/bots_soak.tscn"
# The gates of the plan: a median within this many rounds and a Kolmogorov distance under this.
MEDIAN_GATE = 1.5
KS_GATE = 0.2
# The spend gate carried from the shop soak (#228): points spent over earned within this share of the simulator's.
STUCK_SHARE_GATE = 0.01
SPEND_GATE = 0.20
CATEGORY_OF_PREFIX = {
    "door_": "door",
    "weapon_": "weapon",
    "crane_": "crane",
    "tonic_": "tonic",
    "fuel_": "fuel",
    "grenade": "grenades",
    "ammo_": "ammo",
    "upgrade_": "upgrade",
}


@dataclass(frozen=True)
class Cell:
    profile: str
    bots: int
    order: str = "roam"
    person: bool = False

    @property
    def name(self) -> str:
        return f"{self.profile}_{self.bots}{'_' + self.order if self.order != 'roam' or self.person else ''}{'_person' if self.person else ''}"

    @property
    def sim_skill(self) -> str:
        return PROFILES[self.profile]


def parity_cells() -> list[Cell]:
    return [Cell(profile, bots) for profile in PROFILES for bots in TEAM_SIZES]


def order_cells() -> list[Cell]:
    return [Cell("regular", 3, order, True) for order in ORDERS]


def find_kit() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "repos" / "gdstudio" / "python").is_dir():
            return parent / "repos" / "gdstudio"
        if (parent / "gdstudio" / "python").is_dir():
            return parent / "gdstudio"
    sys.exit("no GDStudio workspace around this checkout")


def godot_path() -> str:
    kit = find_kit()
    out = subprocess.run(
        ["uv", "run", "--project", str(kit / "python"), "gds", "tool", "path", "godot"],
        capture_output=True,
        text=True,
        check=True,
    )
    return out.stdout.strip()


# --- Running ---


def chunk_file(out: Path, cell: Cell, seed: int) -> Path:
    return out / "chunks" / f"{cell.name}_{seed}.jsonl"


def run_chunk(
    godot: str,
    out: Path,
    cell: Cell,
    seed: int,
    nights: int,
    max_round: int,
    timeout: int,
    stall: int = 8,
    tune: str = "",
) -> str:
    """Plays `nights` nights of `cell` from `seed` and keeps what the soak printed. Returns a line for the log."""
    path = chunk_file(out, cell, seed)
    if path.exists() and '"SOAKCELL"' in path.read_text(encoding="utf-8"):
        return f"{path.name}: already done"
    path.parent.mkdir(parents=True, exist_ok=True)
    args = [
        godot,
        "--headless",
        "--path",
        str(GAME),
        SCENE,
        "--fixed-fps",
        "60",
        "--",
        f"--profile={cell.profile}",
        f"--bots={cell.bots}",
        f"--order={cell.order}",
        f"--nights={nights}",
        f"--seed={seed}",
        f"--max-round={max_round}",
        f"--stall-minutes={stall}",
        "--quiet",
    ]
    if cell.person:
        args.append("--person")
    if tune:
        args.append(f"--tune={tune}")
    started = time.time()
    try:
        done = subprocess.run(
            args, check=False, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace"
        )
        text = done.stdout + done.stderr
        status = f"exit {done.returncode}"
    except subprocess.TimeoutExpired as late:
        text = (
            (late.stdout or b"").decode("utf-8", "replace") if isinstance(late.stdout, bytes) else (late.stdout or "")
        )
        status = "timed out"
    lines = [line for line in text.splitlines() if line.startswith(("SOAKNIGHT ", "SOAKCELL "))]
    # What the engine printed that is an error, besides the nights: the report counts it.
    errors = [line for line in text.splitlines() if line.startswith(("ERROR", "SCRIPT ERROR", "USER ERROR"))]
    records = []
    for line in lines:
        kind, _, body = line.partition(" ")
        records.append({"kind": kind, "data": json.loads(body)})
    for line in errors[:20]:
        records.append({"kind": "ENGINE", "data": {"line": line}})
    # One JSON object a line, so a stopped chunk keeps its finished nights.
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record["data"] | {"_kind": record["kind"]}) + "\n")
        if status == "timed out":
            handle.write(json.dumps({"_kind": "TIMEOUT", "seed": seed}) + "\n")
    played = sum(1 for r in records if r["kind"] == "SOAKNIGHT")
    return f"{path.name}: {played} nights, {status}, {time.time() - started:.0f} s"


def sim_cell(godot: str, out: Path, cell: Cell, nights: int, seed: int) -> dict:
    path = out / "sim" / f"{cell.sim_skill}_{cell.bots}.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            godot,
            "--headless",
            "--path",
            str(GAME),
            "-s",
            "res://tools/balance/balance_cli.gd",
            "--",
            f"--skill={cell.sim_skill}",
            f"--players={cell.bots}",
            f"--nights={nights}",
            f"--seed={seed}",
            f"--out={path}",
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=1800,
    )
    return json.loads(path.read_text(encoding="utf-8"))


def command_run(args: argparse.Namespace) -> None:
    out = Path(args.out).resolve()
    godot = godot_path()
    cells = []
    if args.set in ("parity", "all"):
        cells += parity_cells()
    if args.set in ("orders", "all"):
        cells += order_cells()
    if args.cells:
        wanted = set(args.cells.split(","))
        cells = [c for c in cells if c.name in wanted]
    jobs = []
    for cell in cells:
        for first in range(0, args.nights, args.chunk):
            jobs.append((cell, args.seed + first, min(args.chunk, args.nights - first)))
    print(f"{len(jobs)} chunks of up to {args.chunk} nights on {args.jobs} processes", flush=True)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [
            pool.submit(run_chunk, godot, out, cell, seed, count, args.max_round, args.timeout, args.stall, args.tune)
            for cell, seed, count in jobs
        ]
        for future in futures:
            print(future.result(), flush=True)
    command_merge(args)


# --- Reading ---


def kolmogorov(a: list[int], b: list[int]) -> float:
    """The largest gap between the two empirical distributions of a round reached."""
    if not a or not b:
        return float("nan")
    top = max(max(a), max(b))
    gap = 0.0
    for r in range(1, top + 1):
        gap = max(gap, abs(sum(1 for v in a if v <= r) / len(a) - sum(1 for v in b if v <= r) / len(b)))
    return gap


def median_round(rounds: list[int]) -> int:
    """The round half the nights reach (the simulator's reading: the last round with survival of 0.5 or more)."""
    best = 0
    for r in range(1, max(rounds) + 1):
        if sum(1 for v in rounds if v >= r) / len(rounds) >= 0.5:
            best = r
    return best


def sim_rounds(cell: dict, cap: int) -> list[int]:
    """The rounds each simulated night reached, rebuilt from the cell's counts of nights that started a round."""
    reached = cell["reached"]
    nights = int(cell["nights"])
    rounds: list[int] = []
    for r in range(1, len(reached)):
        count = round(reached[r])
        next_count = round(reached[r + 1]) if r + 1 < len(reached) else 0
        rounds += [min(r, cap)] * (count - next_count)
    return rounds[:nights]


def read_nights(out: Path) -> dict[str, list[dict]]:
    found: dict[str, list[dict]] = {}
    for path in sorted((out / "chunks").glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("_kind") == "SOAKNIGHT":
                found.setdefault(record["cell"] if "cell" in record else cell_name_of(record), []).append(record)
    return found


def cell_name_of(record: dict) -> str:
    bots = len(record["bots"])
    person = bool(record.get("person"))
    return Cell(str(record["profile"]), bots, str(record["order"]), person).name


def category_of(item: str) -> str:
    for prefix, category in CATEGORY_OF_PREFIX.items():
        if item.startswith(prefix):
            return category
    return "other"


def bot_stats(nights: list[dict]) -> dict:
    shots = hits = pellets = heads = kills = 0
    attempts = successes = downs = 0
    earned = spent = 0
    up = 0.0
    for night in nights:
        for bot in night["bots"]:
            shots += bot["shots"]
            hits += bot["shot_hits"]
            pellets += bot["pellet_hits"]
            heads += bot["heads"]
            kills += bot["kills"]
            attempts += bot["revive_attempts"]
            successes += bot["revive_successes"]
            downs += bot["downs"]
            earned += bot["points_earned"]
            spent += bot["points_spent"]
            up += bot["up_seconds"]
    total_kills = sum(n["kills_total"] for n in nights)
    return {
        "hit_rate": hits / shots if shots else 0.0,
        "head_share": heads / pellets if pellets else 0.0,
        "kill_share": kills / total_kills if total_kills else 0.0,
        "kills_per_bot_minute": kills / (up / 60.0) if up else 0.0,
        "revive_attempts": attempts,
        "revive_success": successes / attempts if attempts else None,
        "downs_per_bot_hour": downs / (up / 3600.0) if up else 0.0,
        "spend_ratio": spent / earned if earned else 0.0,
        "shots": shots,
    }


def spend_by_category(nights: list[dict]) -> dict[str, float]:
    total: dict[str, float] = {}
    earned = 0
    for night in nights:
        for bot in night["bots"]:
            earned += bot["points_earned"]
            for category, points in bot["spent"].items():
                total[category] = total.get(category, 0) + points
    return {category: points / earned if earned else 0.0 for category, points in total.items()}


def gate_counts(nights: list[dict]) -> dict[str, int]:
    """How many nights broke each gate, by the leading words of what was broken."""
    counts: dict[str, int] = {}
    for night in nights:
        seen = set()
        for broken in night["broken"]:
            key = gate_key(broken)
            if key not in seen:
                seen.add(key)
                counts[key] = counts.get(key, 0) + 1
    return counts


def gate_key(broken: str) -> str:
    for needle, key in [
        ("engine errors", "engine error"),
        ("rejected-buy", "rejected-buy loop"),
        ("stuck for", "stuck episode over 10 s"),
        ("with a zombie in view", "idle with a zombie in view over 5 s"),
        ("lost its brain", "brain disabled"),
        ("would not end", "a round that would not end"),
        ("under Roam", "idle under Roam over 8 s"),
        ("beyond 25 m", "beyond 25 m of the person over 20 s"),
        ("held the spot", "off the Hold spot"),
    ]:
        if needle in broken:
            return key
    return broken


def merge_cell(cell: Cell, nights: list[dict], sim: dict | None, cap: int) -> dict:
    rounds = [min(int(n["round"]), cap) for n in nights]
    row = {
        "cell": cell.name,
        "profile": cell.profile,
        "bots": cell.bots,
        "order": cell.order,
        "person": cell.person,
        "nights": len(nights),
        "median_round": median_round(rounds) if rounds else None,
        "mean_round": statistics.fmean(rounds) if rounds else None,
        "capped": sum(1 for n in nights if n["reason"] != "over"),
        "wall_seconds_mean": statistics.fmean(n["wall_seconds"] for n in nights) if nights else None,
        "game_minutes_mean": statistics.fmean(n["game_seconds"] for n in nights) / 60.0 if nights else None,
        "stats": bot_stats(nights) if nights else {},
        "spend": spend_by_category(nights) if nights else {},
        "gates": gate_counts(nights),
        "broken_nights": [n["seed"] for n in nights if n["broken"]],
        "survival": {str(r): sum(1 for v in rounds if v >= r) / len(rounds) for r in range(1, cap + 1)}
        if rounds
        else {},
    }
    stuck = sum(b["stuck_seconds"] for n in nights for b in n["bots"])
    walking = sum(b["walking_seconds"] for n in nights for b in n["bots"])
    row["stuck_share"] = stuck / walking if walking else 0.0
    # A bot holding a spot walks a few seconds a night, and a bot giving way to the person in that walk is a
    # large share of it: the Hold order is held to the 10 s episode only (docs/research/bots.md, Orders).
    if row["stuck_share"] > STUCK_SHARE_GATE and cell.order != "hold":
        row["gates"]["stuck share over 1% of walking time"] = 1
    if sim is not None and rounds:
        simulated = sim_rounds(sim, cap)
        row["sim_skill"] = cell.sim_skill
        row["sim_nights"] = len(simulated)
        row["sim_median_round"] = median_round(simulated)
        row["median_gap"] = (row["median_round"] or 0) - row["sim_median_round"]
        row["ks"] = kolmogorov(rounds, simulated)
        row["sim_spend_ratio"] = sim["spent_total"] / sim["earned_total"] if sim["earned_total"] else 0.0
        by_category: dict[str, float] = {}
        for item, points in sim["spent_on"].items():
            category = category_of(item)
            by_category[category] = by_category.get(category, 0) + points
        players = int(sim["players"])
        row["sim_spend_share"] = {
            c: p / players / sim["earned_total"] if sim["earned_total"] else 0.0 for c, p in by_category.items()
        }
        row["parity_ok"] = abs(row["median_gap"]) <= MEDIAN_GATE and row["ks"] <= KS_GATE
    return row


def command_merge(args: argparse.Namespace) -> None:
    out = Path(args.out).resolve()
    if args.sim_nights > 0:
        godot = godot_path()
        for cell in parity_cells():
            if (out / "chunks").is_dir() and any((out / "chunks").glob(f"{cell.name}_*.jsonl")):
                sim_cell(godot, out, cell, args.sim_nights, args.sim_seed)
    nights_by_cell = read_nights(out)
    cap = args.max_round
    rows = []
    for cell in parity_cells() + order_cells():
        nights = nights_by_cell.get(cell.name, [])
        if not nights:
            continue
        sim_path = out / "sim" / f"{cell.sim_skill}_{cell.bots}.json"
        sim = json.loads(sim_path.read_text(encoding="utf-8")) if sim_path.exists() and not cell.person else None
        rows.append(merge_cell(cell, nights, sim, cap))
    engine_lines = []
    for path in sorted((out / "chunks").glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip() and json.loads(line).get("_kind") == "ENGINE":
                engine_lines.append(json.loads(line)["line"])
    report = {"cap": cap, "cells": rows, "engine_errors": engine_lines}
    (out / "report.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    (out / "report.md").write_text(markdown(report), encoding="utf-8")
    if args.chart:
        draw_chart(out, rows, cap)
    print(markdown(report))
    if args.gate:
        failed = [r["cell"] for r in rows if r["gates"] or (args.gate_parity and r.get("parity_ok") is False)]
        if failed or engine_lines:
            sys.exit(f"gates broken in: {', '.join(failed) or 'the engine log'}")


def draw_chart(out: Path, rows: list[dict], cap: int) -> None:
    """The survival curves of the bots and of the simulator, one panel for each parity cell (needs matplotlib)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    surface, ink, bots_color, sim_color = "#fcfcfb", "#0b0b0b", "#2a78d6", "#eb6834"
    fig, axes = plt.subplots(3, 3, figsize=(11, 8), sharex=True, sharey=True, facecolor=surface)
    rounds = list(range(1, cap + 1))
    for ax in axes.flat:
        ax.set_facecolor(surface)
    for row in rows:
        if row["person"] or "sim_median_round" not in row:
            continue
        ax = axes[list(PROFILES).index(row["profile"])][TEAM_SIZES.index(row["bots"])]
        sim = json.loads((out / "sim" / f"{row['sim_skill']}_{row['bots']}.json").read_text(encoding="utf-8"))
        simulated = sim_rounds(sim, cap)
        ax.step(rounds, [row["survival"][str(r)] for r in rounds], where="post", color=bots_color, label="bots")
        ax.step(
            rounds,
            [sum(1 for v in simulated if v >= r) / len(simulated) for r in rounds],
            where="post",
            color=sim_color,
            label="simulator",
        )
        ax.set_title(
            f"{row['profile']} x{row['bots']}: median {row['median_round']} / {row['sim_median_round']}, "
            f"KS {row['ks']:.2f}",
            fontsize=9,
            color=ink,
        )
        ax.grid(color="#e7e6e1")
        ax.set_xticks(range(2, cap + 1, 2))
    axes[0][0].legend(loc="lower left", fontsize=8)
    for ax in axes[2]:
        ax.set_xlabel("round reached", color=ink)
    for ax in axes[:, 0]:
        ax.set_ylabel("share of nights", color=ink)
    fig.suptitle("Bots against the balance simulator: share of nights that reach each round", color=ink)
    fig.tight_layout()
    fig.savefig(out / "parity.png", dpi=110, facecolor=surface)


def pct(value: float | None) -> str:
    return "n/a" if value is None else f"{100.0 * value:.0f}%"


def markdown(report: dict) -> str:
    lines = ["# Bot soak and parity report", ""]
    parity = [r for r in report["cells"] if not r["person"]]
    orders = [r for r in report["cells"] if r["person"]]
    lines += [
        f"Round cap {report['cap']} (a night that starts it counts as reaching it, in the bots and in the simulator).",
        "",
        "## Parity with the balance simulator",
        "",
        "| Cell | Nights | Median round | Sim median | Gap | Kolmogorov | Parity | Capped |",
        "| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |",
    ]
    for r in parity:
        lines.append(
            f"| {r['profile']} x{r['bots']} (sim {PROFILES[r['profile']]}) | {r['nights']} | {r['median_round']} |"
            f" {r.get('sim_median_round', 'n/a')} | {r.get('median_gap', 'n/a')} |"
            f" {r['ks']:.2f} | {'yes' if r.get('parity_ok') else 'NO'} | {r['capped']} |"
            if "ks" in r
            else f"| {r['cell']} | {r['nights']} | {r['median_round']} | n/a | n/a | n/a | n/a | {r['capped']} |"
        )
    lines += [
        "",
        "## What the bots measured",
        "",
        "| Cell | Hit rate | Head share | Kills per bot-minute | Revive success (tries) | Downs per bot-hour | Spend ratio (sim) | Stuck share | Wall s a night |",
        "| --- | ---: | ---: | ---: | --- | ---: | --- | ---: | ---: |",
    ]
    for r in report["cells"]:
        s = r["stats"]
        revive = "n/a" if s["revive_success"] is None else f"{pct(s['revive_success'])} ({s['revive_attempts']})"
        sim_ratio = f"{r['sim_spend_ratio']:.2f}" if "sim_spend_ratio" in r else "n/a"
        lines.append(
            f"| {r['cell']} | {pct(s['hit_rate'])} | {pct(s['head_share'])} | {s['kills_per_bot_minute']:.2f} |"
            f" {revive} | {s['downs_per_bot_hour']:.1f} | {s['spend_ratio']:.2f} ({sim_ratio}) |"
            f" {100.0 * r['stuck_share']:.2f}% | {r['wall_seconds_mean']:.0f} |"
        )
    lines += ["", "## Gates", "", "| Cell | Nights | Nights that broke a gate | Which |", "| --- | ---: | ---: | --- |"]
    for r in report["cells"]:
        which = ", ".join(f"{k} x{v}" for k, v in sorted(r["gates"].items())) or "none"
        lines.append(f"| {r['cell']} | {r['nights']} | {len(r['broken_nights'])} | {which} |")
    if orders:
        lines += ["", "## Orders with a person", ""]
        for r in orders:
            lines.append(f"- {r['cell']}: median round {r['median_round']}, {r['nights']} nights")
    if report["engine_errors"]:
        lines += ["", "## Engine errors", ""] + [f"- `{line}`" for line in report["engine_errors"][:20]]
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run", help="play the chunks, then merge")
    merge = sub.add_parser("merge", help="read the chunks into the report")
    for p in (run, merge):
        p.add_argument("--out", required=True)
        p.add_argument("--max-round", type=int, default=16)
        p.add_argument("--gate", action="store_true", help="exit 1 when a gate is broken")
        p.add_argument("--gate-parity", action="store_true", help="with --gate: a cell off the simulator fails too")
        p.add_argument("--chart", action="store_true", help="draw parity.png (needs matplotlib)")
        p.add_argument("--sim-nights", type=int, default=300, help="nights of each simulator cell (0: none)")
        p.add_argument("--sim-seed", type=int, default=1)
    run.add_argument("--nights", type=int, default=100)
    run.add_argument("--seed", type=int, default=1)
    run.add_argument("--chunk", type=int, default=5)
    run.add_argument("--jobs", type=int, default=3)
    run.add_argument("--set", choices=["parity", "orders", "all"], default="all")
    run.add_argument("--cells", default="", help="only these cells, by name, comma separated")
    run.add_argument("--tune", default="", help="profile fields set for every bot, field=value,field=value")
    run.add_argument("--stall", type=int, default=8, help="game minutes after which a round counts as stalled")
    run.add_argument("--timeout", type=int, default=3600, help="seconds one chunk may take")
    args = parser.parse_args()
    {"run": command_run, "merge": command_merge}[args.command](args)


if __name__ == "__main__":
    main()
