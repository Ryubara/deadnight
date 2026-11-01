#!/usr/bin/env python3
"""Keeps two status labels true on every open pull request: `S-conflict` and `S-ci-failing`.

  S-conflict    GitHub reports the pull request cannot be merged because it conflicts with its base.
  S-ci-failing  a required check (merge.required_checks in .github/conventions.yml) failed on the latest head commit.

A label is added when its condition holds and removed as soon as it stops holding. What the workflow
(.github/workflows/pr-status.yml) passes in:

  --pr N      one pull request (it was opened, pushed to or reopened)
  --sha SHA   the open pull requests whose head is that commit (a workflow finished on it)
  --all       every open pull request (the default branch moved, so any of them may now conflict)

Standard library plus PyYAML (only to read the conventions). Needs `gh` and GH_TOKEN; GH_REPO names the repository.
Nothing from a pull request is run: a number, a sha and GitHub's own answers are the only inputs, and each is
validated before it is used. Exit 0 when every pull request was evaluated (a mergeability GitHub has not computed
within the bound is left as it was and reported as a warning), 1 on an API error, 2 when the conventions are unusable.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

CONFLICT = "S-conflict"
FAILING = "S-ci-failing"
LABELS = (CONFLICT, FAILING)

# A check run that ended in one of these failed. `cancelled` is not here: a newer push cancels the older run, and a
# cancelled run says nothing about the code. `skipped` and `neutral` are not failures either.
FAILED = frozenset({"failure", "timed_out", "startup_failure"})

CONVENTIONS = Path(".github/conventions.yml")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")

# GitHub computes `mergeable` lazily: the first request after a push or a merge answers null and starts the work.
POLL_ATTEMPTS = 10
POLL_SECONDS = 3.0


class Unusable(Exception):
    """The conventions or the invocation cannot be used (exit 2)."""


class ApiError(Exception):
    """A `gh api` call failed (exit 1)."""


# --------------------------------------------------------------------------------------------------------------------
# The decisions: pure functions of GitHub's answers
# --------------------------------------------------------------------------------------------------------------------


def has_conflict(pr: dict[str, Any]) -> bool | None:
    """True when the pull request conflicts with its base, False when it does not, None while GitHub has not decided.

    `mergeable` is true or false once computed and null before. It is false for a conflict only: a pull request that
    is blocked by a missing review or a red check is still `mergeable: true`.
    """
    mergeable = pr.get("mergeable")
    if mergeable is None:
        return None
    return mergeable is False


def failing_checks(check_runs: list[dict[str, Any]], required: list[str]) -> list[str]:
    """The names of the required checks that failed. With no required list, every check counts."""
    names = {run["name"] for run in check_runs if run.get("conclusion") in FAILED}
    if required:
        names &= set(required)
    return sorted(names)


def label_changes(current: set[str], conflict: bool | None, failing: bool | None) -> tuple[list[str], list[str]]:
    """(labels to add, labels to remove). A condition that is None (unknown) leaves its label as it is."""
    add: list[str] = []
    remove: list[str] = []
    for label, state in ((CONFLICT, conflict), (FAILING, failing)):
        if state is True and label not in current:
            add.append(label)
        elif state is False and label in current:
            remove.append(label)
    return add, remove


# --------------------------------------------------------------------------------------------------------------------
# GitHub
# --------------------------------------------------------------------------------------------------------------------


class Client:
    """The few GitHub calls this needs, through `gh api` (so GH_TOKEN, proxies and retries are gh's business)."""

    def __init__(self, repo: str) -> None:
        if not REPO_RE.match(repo):
            raise Unusable(f"unexpected repository name {repo!r}")
        self.repo = repo

    def _run(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["gh", "api", *args], capture_output=True, text=True, encoding="utf-8", check=False)

    def get(self, path: str, paginate: bool = False) -> Any:
        extra = ["--paginate", "--slurp"] if paginate else []
        done = self._run(f"repos/{self.repo}/{path}", *extra)
        if done.returncode != 0:
            raise ApiError(f"GET {path}: {done.stderr.strip()}")
        data = json.loads(done.stdout)
        if paginate:  # --slurp: a list of pages; a page is a list, or an object holding a list
            flat: list[Any] = []
            for page in data:
                flat.extend(page if isinstance(page, list) else [page])
            return flat
        return data

    def get_or_none(self, path: str) -> Any:
        done = self._run(f"repos/{self.repo}/{path}")
        return json.loads(done.stdout) if done.returncode == 0 else None

    def post(self, path: str, **fields: str) -> None:
        args = [a for key, value in fields.items() for a in ("-f", f"{key}={value}")]
        done = self._run("--method", "POST", f"repos/{self.repo}/{path}", *args)
        if done.returncode != 0 and "already_exists" not in done.stdout:
            raise ApiError(f"POST {path}: {done.stderr.strip()} {done.stdout.strip()}")

    def delete(self, path: str) -> None:
        done = self._run("--method", "DELETE", f"repos/{self.repo}/{path}")
        if done.returncode != 0 and "404" not in done.stderr:
            raise ApiError(f"DELETE {path}: {done.stderr.strip()}")

    def check_runs(self, sha: str) -> list[dict[str, Any]]:
        """The latest run of each check on a commit (a re-run replaces the run it repeats)."""
        pages = self.get(f"commits/{sha}/check-runs?filter=latest&per_page=100", paginate=True)
        runs: list[dict[str, Any]] = []
        for page in pages:
            runs.extend(page.get("check_runs", []) if isinstance(page, dict) else [])
        return runs


def load_conventions(path: Path = CONVENTIONS) -> tuple[list[str], dict[str, dict[str, str]]]:
    """(merge.required_checks, the definitions of the two status labels in labels.list)."""
    import yaml  # imported here so the decisions above can be used and tested without PyYAML

    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as err:
        raise Unusable(f"cannot read {path}: {err}") from err
    if not isinstance(data, dict):
        raise Unusable(f"{path} must be a mapping")
    required = [str(name) for name in (data.get("merge") or {}).get("required_checks", [])]
    listed = {item["name"]: item for item in (data.get("labels") or {}).get("list", []) if isinstance(item, dict)}
    missing = [label for label in LABELS if label not in listed]
    if missing:
        raise Unusable(f"labels.list in {path} does not define {', '.join(missing)}")
    return required, {label: listed[label] for label in LABELS}


def ensure_label(client: Client, definition: dict[str, str], known: set[str]) -> None:
    """Create a label from its definition in the conventions when the repository does not have it yet."""
    name = definition["name"]
    if name in known:
        return
    if client.get_or_none(f"labels/{name}") is None:
        client.post(
            "labels", name=name, color=str(definition["color"]), description=str(definition.get("description", ""))
        )
        print(f"created the label {name}")
    known.add(name)


def settled(client: Client, number: int, attempts: int, sleep: Callable[[float], None]) -> dict[str, Any]:
    """The pull request, asked again until GitHub has computed `mergeable` or the bound is reached."""
    pr = client.get(f"pulls/{number}")
    for _ in range(attempts - 1):
        if has_conflict(pr) is not None or pr.get("state") != "open":
            break
        sleep(POLL_SECONDS)
        pr = client.get(f"pulls/{number}")
    return pr


def sync_pr(
    client: Client,
    number: int,
    required: list[str],
    definitions: dict[str, dict[str, str]],
    known: set[str],
    attempts: int = POLL_ATTEMPTS,
    sleep: Callable[[float], None] = time.sleep,
    dry_run: bool = False,
) -> str:
    """Bring one open pull request's two labels in line with GitHub's answers; returns a line saying what happened."""
    pr = settled(client, number, attempts, sleep)
    if pr.get("state") != "open":
        return f"#{number}: not open, skipped"
    conflict = has_conflict(pr)
    failed = failing_checks(client.check_runs(pr["head"]["sha"]), required)
    current = {label["name"] for label in pr.get("labels", [])}
    add, remove = label_changes(current, conflict, bool(failed))
    notes = []
    for label in add:
        if not dry_run:
            ensure_label(client, definitions[label], known)
            client.post(f"issues/{number}/labels", **{"labels[]": label})
        notes.append(f"added {label}")
    for label in remove:
        if not dry_run:
            client.delete(f"issues/{number}/labels/{label}")
        notes.append(f"removed {label}")
    state = f"conflict={conflict}, failing={failed or False}"
    line = f"#{number}: {state}; " + ("; ".join(notes) if notes else "no change")
    if conflict is None:  # an annotation has to start its own line
        warning = (
            f"::warning::#{number}: GitHub has not computed mergeable after {attempts} tries; {CONFLICT} left as is"
        )
        return f"{warning}\n{line}"
    return line


def open_numbers(client: Client, sha: str | None) -> list[int]:
    """The open pull requests to look at: every one, or those whose head is `sha`."""
    if sha is None:
        return [pr["number"] for pr in client.get("pulls?state=open&per_page=100", paginate=True)]
    found = client.get(f"commits/{sha}/pulls?per_page=100", paginate=True)
    return [pr["number"] for pr in found if pr.get("state") == "open" and pr.get("head", {}).get("sha") == sha]


def main(argv: list[str] | None = None, client: Client | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    which = parser.add_mutually_exclusive_group(required=True)
    which.add_argument("--pr", type=int, help="one pull request by number")
    which.add_argument("--sha", help="the open pull requests whose head is this commit")
    which.add_argument("--all", action="store_true", help="every open pull request")
    parser.add_argument("--repo", help="owner/name (default: GH_REPO)")
    parser.add_argument("--conventions", type=Path, default=CONVENTIONS)
    parser.add_argument("--dry-run", action="store_true", help="say what would change; change nothing")
    args = parser.parse_args(argv)
    try:
        if args.sha is not None and not SHA_RE.match(args.sha):
            raise Unusable("--sha must be a full 40-character commit sha")
        required, definitions = load_conventions(args.conventions)
        if client is None:
            import os

            client = Client(args.repo or os.environ.get("GH_REPO", ""))
        numbers = [args.pr] if args.pr is not None else open_numbers(client, None if args.all else args.sha)
        for number in numbers:  # first request of each starts GitHub's computation, so later ones wait less
            client.get(f"pulls/{number}")
        known: set[str] = set()
        for number in numbers:
            print(sync_pr(client, number, required, definitions, known, dry_run=args.dry_run))
        if not numbers:
            print("no open pull request to look at")
    except Unusable as err:
        print(f"unusable: {err}", file=sys.stderr)
        return 2
    except ApiError as err:
        print(f"::error::{err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
