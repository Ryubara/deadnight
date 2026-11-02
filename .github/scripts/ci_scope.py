"""Which parts of the repository a change touches, so `ci` starts only the jobs that can be affected.

    gh api --paginate repos/OWNER/REPO/pulls/N/files --jq '.[].filename' | python .github/scripts/ci_scope.py
    python .github/scripts/ci_scope.py --all        # a push to the default branch, a manual run: everything
    python .github/scripts/ci_scope.py --self-test

Prints `name=true|false` lines for $GITHUB_OUTPUT:

- `godot`: anything the game's import and tests can see. False only when every changed file is documentation
  (`docs/**`, any `*.md`, `.github/ISSUE_TEMPLATE/**`) or lives where the game never looks (`deploy/`, `spikes/`,
  `tools/web_smoke/`), so a docs-only pull request skips the `godot` job.
- `web`: anything the browser build can see: the same, and also `game/tests/` (the export's `exclude_filter` drops it),
  so a pull request that only adds tests skips the `web` job.
- `docs`: the site could change (`docs/**`, `mkdocs.yml`, `requirements-docs.txt`, any `*.md`): the `mkdocs` job.
- `markdown`: any `*.md` or the markdownlint rules: the `markdownlint` job.
- `workflows`: `.github/workflows/**`: the `actionlint` job.
- `backend`: `spikes/backend/**` except Markdown, or the `ci.yml` workflow itself: the `backend` job (the platform
  backend's own tests, #558).

An empty list (the API listed nothing) or a list of 3000 files (the API's limit, so it may be cut short) turns everything
on: a job that should have run never silently does not.
"""

from __future__ import annotations

import re
import sys

LIMIT = 3000
DOC_ONLY = re.compile(r"^(docs/|\.github/ISSUE_TEMPLATE/)|\.md$")
# Not seen by the game's import and tests, and not by the web export (its own scripts run in the `web` job).
NOT_GAME = re.compile(r"^(deploy/|spikes/)|\.md$|^(docs/|\.github/ISSUE_TEMPLATE/)")
NOT_GODOT = re.compile(NOT_GAME.pattern + r"|^tools/web_smoke/")
NOT_WEB = re.compile(NOT_GAME.pattern + r"|^game/tests/")
SITE = re.compile(r"^(docs/|mkdocs\.yml$|requirements-docs\.txt$)|\.md$")
MARKDOWN = re.compile(r"^\.markdownlint|\.md$")
WORKFLOWS = re.compile(r"^\.github/workflows/")
BACKEND = re.compile(r"^(spikes/backend/(?!.*\.md$)|\.github/workflows/ci\.yml$)")


def scope(files: list[str]) -> dict[str, bool]:
    """The flags for a list of changed files."""
    if not files or len(files) >= LIMIT:
        return {"godot": True, "web": True, "docs": True, "markdown": True, "workflows": True, "backend": True}
    return {
        "godot": any(not NOT_GODOT.search(f) for f in files),
        "web": any(not NOT_WEB.search(f) for f in files),
        "docs": any(SITE.search(f) for f in files),
        "markdown": any(MARKDOWN.search(f) for f in files),
        "workflows": any(WORKFLOWS.search(f) for f in files),
        "backend": any(BACKEND.search(f) for f in files),
    }


def _self_test() -> None:
    everything = {"godot": True, "web": True, "docs": True, "markdown": True, "workflows": True, "backend": True}

    def flags(*files: str) -> str:
        return " ".join(name for name, on in scope(list(files)).items() if on) or "-"

    assert scope([]) == everything
    assert scope([f"game/{i}.gd" for i in range(LIMIT)]) == everything
    assert flags("docs/research/hip-fire.md", "docs/design/hud.md") == "docs markdown"
    assert flags("README.md") == "docs markdown"
    assert flags(".github/ISSUE_TEMPLATE/bug.yml") == "-"
    assert flags("game/gameplay/player/player.gd") == "godot web"
    assert flags("game/gameplay/player/player.gd", "docs/design/animation.md") == "godot web docs markdown"
    assert flags(".github/workflows/ci.yml") == "godot web workflows backend"
    assert flags(".github/workflows/pr.yml") == "godot web workflows"
    # Only tests: the game's tests run, the web export does not contain them.
    assert flags("game/tests/player/test_aim_release.gd", "game/tests/player/test_aim_release.gd.uid") == "godot"
    assert flags("game/tests/player/test_x.gd", "docs/research/x.md") == "godot docs markdown"
    # A test next to game code still builds the web.
    assert flags("game/tests/player/test_x.gd", "game/gameplay/player/player.gd") == "godot web"
    # The deploy files and the browser scripts are not the game.
    assert flags("deploy/web/Caddyfile") == "-"
    # The platform backend's own tests: its sources and tests, not its README, and not the game.
    assert flags("spikes/backend/src/lobby.ts") == "backend"
    assert flags("spikes/backend/test/lobby.test.ts", "spikes/backend/package-lock.json") == "backend"
    assert flags("spikes/backend/README.md") == "docs markdown"
    assert flags("tools/web_smoke/smoke.py") == "web"
    assert flags("tools/audio/analyze.py") == "godot web"
    # A markdown file inside the game is documentation too.
    assert flags("game/assets/audio/eleven/LICENSE.md") == "docs markdown"
    assert flags("mkdocs.yml") == "godot web docs"
    assert flags(".markdownlint.yaml") == "godot web markdown"
    print("ci_scope self-test passed")


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        _self_test()
        return 0
    flags = scope([]) if "--all" in argv else scope([line.strip() for line in sys.stdin if line.strip()])
    for name, value in flags.items():
        print(f"{name}={'true' if value else 'false'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
