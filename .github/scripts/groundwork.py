#!/usr/bin/env python3
"""Groundwork's portable checker: reads .github/conventions.yml and enforces it.

One file, standard library plus PyYAML, so a repository set up by Groundwork needs nothing from Coney.
Run it as `uv run --with pyyaml python .github/scripts/groundwork.py <command>`; `--help` lists the commands.

Exit codes: 0 passed, 1 a rule was broken (or drift found), 2 the conventions file or the invocation is unusable.
Text that a stranger controls (a title, a description) only ever arrives on stdin or in a file, never in a command
line, so a workflow can pass it without expanding it into a script.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any

import yaml

CONVENTIONS = Path(".github/conventions.yml")
MARKER = "groundwork-hygiene"  # the hygiene comment starts with <!-- MARKER -->

# Top-level keys and the keys each may hold. An unknown key is an error, so a typo fails loudly instead of being
# ignored (the reference, Coney's checker, does the same).
KNOWN: dict[str, set[str]] = {
    "version": set(),
    "repo": {"default_branch", "wording", "maintainer_decisions", "tools"},
    "paths": {"code", "docs", "generated", "large_file_kb", "pointer_files", "blocks_in"},
    "commits": {"title", "body", "trailers"},
    "pull_requests": {"template", "sections", "filled", "placeholders", "local_paths", "docs_none", "closing",
                      "checklist", "ai_use", "guidance", "screenshots", "issues_affected", "failed_first", "lessons", "kit_docs",
                      "read_first"},
    "merge": {"methods", "squash_title", "squash_message", "auto_merge", "delete_branch_on_merge",
              "linear_history", "required_checks", "ruleset_name", "up_to_date_required", "manual_paths", "hold"},
    "issues": {"blank_issues", "placeholders", "forms", "labels"},
    "labels": {"description_max", "families", "list"},
    "hygiene": {"report_issue", "sweep", "thresholds"},
}


class ConventionsError(Exception):
    """The conventions file is missing or malformed."""


# --------------------------------------------------------------------------------------------------------------------
# Loading and validating the conventions
# --------------------------------------------------------------------------------------------------------------------


def load(path: Path = CONVENTIONS) -> dict[str, Any]:
    """Read the conventions file and refuse unknown keys and wrong types."""
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as err:
        raise ConventionsError(f"cannot read {path}: {err}") from err
    if not isinstance(data, dict):
        raise ConventionsError(f"{path} must be a mapping")
    problems = validate(data)
    if problems:
        raise ConventionsError("; ".join(problems))
    return data


def validate(data: dict[str, Any]) -> list[str]:
    """Return every problem found in a parsed conventions mapping (empty when it is fine)."""
    problems: list[str] = []
    for key, value in data.items():
        if key not in KNOWN:
            problems.append(f"unknown key {key!r}")
        elif KNOWN[key] and not isinstance(value, dict):
            problems.append(f"{key} must be a mapping")
        elif KNOWN[key]:
            problems += [f"unknown key {key}.{sub!r}" for sub in value if sub not in KNOWN[key]]
    if problems:
        return problems
    title = data.get("commits", {}).get("title", {})
    if not title.get("areas") or not title.get("verbs"):
        problems.append("commits.title needs areas and verbs")
    labels = {item["name"] for item in all_labels(data)}
    names = [item.get("name") for item in data.get("labels", {}).get("list", []) if isinstance(item, dict)]
    if len(names) != len(set(names)):
        problems.append("labels.list has a duplicate name")
    for form_name, form in data.get("issues", {}).get("forms", {}).items():
        for label in form.get("labels", []):
            if labels and label not in labels:
                problems.append(f"issues.forms.{form_name} uses the label {label!r}, which labels.list lacks")
    for check in data.get("merge", {}).get("required_checks", []):
        if not isinstance(check, str):
            problems.append("merge.required_checks must be a list of names")
    hold = data.get("merge", {}).get("hold")
    if hold is not None:
        if not (isinstance(hold, dict) and hold.get("label") and hold.get("check") and isinstance(hold.get("app_id"), int)):
            problems.append("merge.hold needs label, check and a numeric app_id")
        else:
            if labels and hold["label"] not in labels:
                problems.append(f"merge.hold uses the label {hold['label']!r}, which labels.list lacks")
            if hold["check"] in data.get("merge", {}).get("required_checks", []):
                problems.append("merge.hold's check stays out of merge.required_checks: a hold is not a failure")
    trailers = data.get("commits", {}).get("trailers")
    if trailers is not None and not (isinstance(trailers, dict) and isinstance(trailers.get("ai_co_author"), dict)
                                     and trailers["ai_co_author"].get("noreply")):
        problems.append("commits.trailers needs ai_co_author with a noreply list")
    pointer = data.get("paths", {}).get("pointer_files")
    if pointer is not None and not (isinstance(pointer, dict) and pointer.get("files") and pointer.get("content")):
        problems.append("paths.pointer_files needs files and content")
    return problems


def all_labels(data: dict[str, Any]) -> list[dict[str, Any]]:
    """labels.list plus the generated area labels: a family with `from_title_areas: true` gets one label per title
    area (`A-<area>`), described by the area's description, so the areas live in one place."""
    labels_rule = data.get("labels", {})
    items = [item for item in labels_rule.get("list", []) if isinstance(item, dict)]
    limit = labels_rule.get("description_max", 100)
    for spec in labels_rule.get("families", {}).values():
        if isinstance(spec, dict) and spec.get("from_title_areas"):
            for area, about in data.get("commits", {}).get("title", {}).get("areas", {}).items():
                text = f"Area: {about}"
                text = text if len(text) <= limit else text[: limit - 3].rstrip() + "..."
                items.append({"name": f"{spec['prefix']}{area}", "color": str(spec.get("color", "c5def5")),
                              "description": text})
    return items


def area_options(conv: dict[str, Any]) -> list[str]:
    """The issue form's Area choices: one `A-<area>` per title area (the generated area label family)."""
    for spec in conv.get("labels", {}).get("families", {}).values():
        if isinstance(spec, dict) and spec.get("from_title_areas"):
            return [f"{spec['prefix']}{area}" for area in conv["commits"]["title"]["areas"]]
    return list(conv["commits"]["title"]["areas"])


# --------------------------------------------------------------------------------------------------------------------
# Titles
# --------------------------------------------------------------------------------------------------------------------


def title_problems(conv: dict[str, Any], title: str) -> list[str]:
    """Check a commit or pull request title against commits.title; return what is wrong."""
    rule = conv["commits"]["title"]
    problems: list[str] = []
    suffix = rule.get("breaking_suffix") or ""
    text = title.strip()
    if len(text) > rule.get("max_length", 72):
        problems.append(f"{len(text)} characters; at most {rule.get('max_length', 72)}")
    body = text[: -len(suffix)].rstrip() if suffix and text.endswith(suffix) else text
    if not rule.get("trailing_period", False) and body.endswith("."):
        problems.append("ends with a period")
    match = re.fullmatch(r"([a-z0-9-]+): ([A-Z][a-z]+) (\S.*)", body)
    if not match:
        problems.append(f"does not match the form {rule.get('form', 'area: Verb the rest')!r}")
        return problems
    area, verb, _ = match.groups()
    if area not in rule["areas"]:
        problems.append(f"area {area!r} is not one of: {', '.join(rule['areas'])}")
    if verb not in rule["verbs"]:
        problems.append(f"verb {verb!r} is not one of: {', '.join(rule['verbs'])}")
    return problems


# --------------------------------------------------------------------------------------------------------------------
# Pull request descriptions
# --------------------------------------------------------------------------------------------------------------------

_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
_IMAGE = re.compile(r"!\[[^\]]*\]\([^)]*\)")
_LOCAL_PATH = re.compile(r"(?<![\w/.-])(?:[A-Za-z]:\\|\.\./\.\./|scratch/)")


def split_sections(body: str) -> dict[str, str]:
    """Split a description into its `## Heading` sections (heading -> text); text before the first is dropped."""
    sections: dict[str, str] = {}
    current: str | None = None
    for line in body.splitlines():
        heading = re.match(r"##\s+(.+?)\s*$", line)
        if heading and not line.startswith("###"):
            current = heading.group(1)
            sections[current] = ""
        elif current is not None:
            sections[current] += line + "\n"
    return sections


def is_empty(text: str, placeholders: list[str]) -> bool:
    """True when a section holds only comments, bullets and template placeholders."""
    stripped = _COMMENT.sub("", text)
    lines = [re.sub(r"^\s*(?:[-*]\s*(?:\[[ xX]\]\s*)?)?", "", ln).strip() for ln in stripped.splitlines()]
    lines = [ln for ln in lines if ln]
    low = {p.lower() for p in placeholders} | {p.lower().rstrip(".") for p in placeholders}
    return all(ln.lower() in low or ln.lower().rstrip(".") in low for ln in lines)


def body_problems(conv: dict[str, Any], body: str) -> list[str]:
    """Check a pull request description against pull_requests (the docs rule is `docs_problems`)."""
    rule = conv["pull_requests"]
    problems: list[str] = []
    sections = split_sections(body)
    wanted: list[str] = rule.get("sections", [])
    present = [name for name in sections if name in wanted]
    for name in wanted:
        if name not in sections:
            problems.append(f"missing the section ## {name}")
    if not problems and present != wanted:
        problems.append(f"sections out of order; expected {', '.join(wanted)}")
    placeholders = rule.get("placeholders", ["..."])
    for name in rule.get("filled", []):
        if name in sections and is_empty(sections[name], placeholders):
            problems.append(f"the section ## {name} is empty or still the template's placeholder")
    if not rule.get("local_paths", False):
        for number, line in enumerate(_IMAGE.sub("", _COMMENT.sub("", body)).splitlines(), 1):
            if _LOCAL_PATH.search(line):
                problems.append(f"line {number} names a path on someone's machine; say it in words instead")
    checklist = rule.get("checklist")
    if checklist and checklist["section"] in sections:
        text = _COMMENT.sub("", sections[checklist["section"]])
        if re.search(r"^\s*[-*]\s*\[ \]", text, re.MULTILINE):
            problems.append(f"the section ## {checklist['section']} has an unticked task; finish it or move it to an issue")
    closing = rule.get("closing")
    if closing:
        for line in _COMMENT.sub("", body).splitlines():
            # Only a line that tries to be a closing line (the keyword, then `:`, `#` or a digit) is held to the
            # form; a sentence that merely starts with the word ("Fixes the two tools ...") is prose.
            if re.match(rf"\s*{re.escape(closing['keyword'])}\s*[:#\d]", line) and not re.fullmatch(
                rf"{re.escape(closing['keyword'])} #\d+", line.strip()
            ):
                problems.append(f"a closing line must read '{closing['form']}', one per line: {line.strip()!r}")
    ai = rule.get("ai_use")
    if ai and ai["section"] in sections:
        text = _COMMENT.sub("", sections[ai["section"]])
        written = _field(text, ai["written_by"]["label"])
        if written not in ai["written_by"]["choices"]:
            problems.append(f"'{ai['written_by']['label']}' must be one of: {'; '.join(ai['written_by']['choices'])}")
        elif written != ai["written_by"]["no_ai"]:
            model = _field(text, ai["model"]["label"])
            if not model or model.lower() == ai["model"]["none"]:
                problems.append(f"'{ai['model']['label']}' must name the model when an AI took part")
    problems += issues_affected_problems(conv, body)
    return problems


def _reasoned(value: str) -> bool:
    """True when `value` is a non-empty reason in parentheses: `(why)`, with one full stop after it allowed."""
    value = value.strip()
    if value.endswith(")."):
        value = value[:-1]
    return value.startswith("(") and value.endswith(")") and len(value.strip("() ")) > 0


def _bullets(text: str) -> list[str]:
    """The non-empty lines of a section without comments and list markers."""
    lines = [re.sub(r"^[-*]\s+", "", ln.strip()) for ln in _COMMENT.sub("", text).splitlines()]
    return [ln for ln in lines if ln]


def issues_affected_problems(conv: dict[str, Any], body: str) -> list[str]:
    """Every other open issue the change partly fixes or makes out of date, one `#N: how` line each, or one line
    `None (reason)` (pull_requests.issues_affected). A missing section is reported by `body_problems`."""
    rule = conv["pull_requests"].get("issues_affected")
    if not rule:
        return []
    section = rule.get("section", "Issues affected")
    none = rule.get("none", "None")
    sections = split_sections(body)
    if section not in sections:
        return [] if section in conv["pull_requests"].get("sections", []) else [f"missing the section ## {section}"]
    placeholders = {p.lower() for p in conv["pull_requests"].get("placeholders", ["..."])}
    lines = [ln for ln in _bullets(sections[section]) if ln.lower() not in placeholders]
    if not lines:
        return [f"the section ## {section} is empty: list each other open issue this partly fixes or makes out of "
                f"date ('#N: what changed for it'), or write '{none} (reason)'"]
    if any(ln.startswith(none) for ln in lines):
        if len(lines) > 1:
            return [f"'{none} (reason)' stands alone in ## {section}; drop it or the issue lines"]
        if not _reasoned(lines[0][len(none):]):
            return [f"'{none}' needs a reason in parentheses: '{none} (why no open issue is affected)'"]
        return []
    bad = [ln for ln in lines if not re.match(r"(?:[\w.-]+/[\w.-]+)?#\d+\s*:\s*\S", ln)]
    return [f"each line of ## {section} reads '#N: what changed for it': {ln!r}" for ln in bad]


_UPLOADED = re.compile(r"(?:!\[[^\]]*\]\(\s*|<img[^>]*src=[\"']?|^\s*)https://(?:github\.com/user-attachments/|"
                       r"user-images\.githubusercontent\.com/|private-user-images\.githubusercontent\.com/)\S+",
                       re.MULTILINE)


def screenshot_problems(conv: dict[str, Any], title: str, body: str) -> list[str]:
    """A pull request in a visual area (pull_requests.screenshots.areas) shows what changed: an uploaded image or
    video in its Screenshots section, or the `none` line with a reason in parentheses."""
    rule = conv["pull_requests"].get("screenshots")
    if not rule:
        return []
    area = title.split(":", 1)[0].strip() if ":" in title else ""
    if area not in rule.get("areas", []):
        return []
    section = rule.get("section", "Screenshots")
    text = _COMMENT.sub("", split_sections(body).get(section, ""))
    none = rule.get("none", "Screenshots: none")
    for line in text.splitlines():
        if line.strip().startswith(none):
            if _reasoned(line.strip()[len(none):]):
                return []
            return [f"'{none}' needs a reason in parentheses: '{none} (why nothing visible changed)'"]
    pair = rule.get("before_after")
    if pair:
        return _before_after_problems(text, area, section, pair)
    if _UPLOADED.search(text):
        return []
    return [f"a `{area}` pull request shows what changed: attach a capture in ## {section} (`gh pr create|edit "
            f"--attach`), or write '{none} (reason)'"]


def _label_at(text: str, label: str) -> re.Match[str] | None:
    """Where a `Label:` (bare, bulleted or in bold) starts a line of `text`."""
    bare = re.escape(label.rstrip(":"))
    return re.search(rf"^[ \t]*(?:[-*][ \t]*)?(?:\*\*{bare}:?\*\*:?|{bare}:)", text, re.MULTILINE)


def _before_after_problems(text: str, area: str, section: str, pair: dict[str, Any]) -> list[str]:
    """A visual pull request shows a before and an after capture; `Before: none (reason)` for something new."""
    before_label, after_label = pair.get("before", "Before:"), pair.get("after", "After:")
    before, after = _label_at(text, before_label), _label_at(text, after_label)
    how = (f"a `{area}` pull request shows what changed in ## {section}: a '{before_label}' and an '{after_label}' "
           f"capture, uploaded (`gh pr create|edit --attach`)")
    if not before or not after or before.start() > after.start():
        return [f"{how}; '{before_label} none (reason)' when it did not exist before"]
    problems = []
    before_text = text[before.end():after.start()].strip()
    if before_text.lower().startswith("none"):
        rest = before_text[4:].strip().splitlines()
        if not rest or not _reasoned(rest[0]):
            problems.append(f"'{before_label} none' needs a reason in parentheses: '{before_label} none (new screen)'")
    elif not _UPLOADED.search(before_text):
        problems.append(f"{how}: the '{before_label}' capture is missing")
    if not _UPLOADED.search(text[after.end():]):
        problems.append(f"{how}: the '{after_label}' capture is missing")
    return problems


def failed_first_problems(conv: dict[str, Any], title: str, body: str) -> list[str]:
    """A pull request whose title verb is in pull_requests.failed_first.verbs (a fix) shows, in its Testing section,
    the test that failed before the change and passes after it: a `Failed first:` line, or `Failed first: none
    (reason)` when no test can show it."""
    rule = conv["pull_requests"].get("failed_first")
    match = re.match(r"\s*[a-z0-9-]+: ([A-Z][a-z]+) ", title)
    if not rule or not match or match.group(1) not in rule.get("verbs", ["Fix"]):
        return []
    label, section = rule.get("label", "Failed first:"), rule.get("section", "Testing")
    text = _COMMENT.sub("", split_sections(body).get(section, ""))
    found = _label_at(text, label)
    rest = text[found.end():].splitlines() if found else []
    value = rest[0].strip() if rest else ""
    placeholders = {p.lower() for p in conv["pull_requests"].get("placeholders", ["..."])}
    if not value or value.lower() in placeholders:
        return [f"a `{match.group(1)}` pull request shows its test failing first: a line '{label} <test> failed "
                f"before the fix (<how>) and passes after' in ## {section}, or '{label} none (reason)'"]
    if value.lower().startswith("none") and not _reasoned(value[4:]):
        return [f"'{label} none' needs a reason in parentheses: '{label} none (why no test can show it)'"]
    return []


def _title_verb(title: str) -> str:
    """The verb of a `area: Verb the rest` title, '' when the title does not follow the form."""
    match = re.match(r"\s*[a-z0-9-]+: ([A-Z][a-z]+) ", title)
    return match.group(1) if match else ""


def _summary_value(conv: dict[str, Any], body: str, rule: dict[str, Any], default_label: str) -> str | None:
    """The value of a `Label:` line in the rule's section (Summary), None when there is no such line or it still holds
    a template placeholder."""
    label, section = rule.get("label", default_label), rule.get("section", "Summary")
    text = _COMMENT.sub("", split_sections(body).get(section, ""))
    found = _label_at(text, label)
    if not found:
        return None
    rest = text[found.end():].splitlines()
    value = rest[0].strip() if rest else ""
    placeholders = {p.lower() for p in conv["pull_requests"].get("placeholders", ["..."])}
    return None if not value or value.lower() in placeholders else value


def self_correction_reasons(rule: dict[str, Any], title: str, history: dict[str, Any]) -> list[str]:
    """Why this pull request counts as an agent correcting its own or earlier work: its title verb (a fix or a
    rework), a required check that failed on an earlier commit of it, or an issue it closes labelled as a bug. Read
    from the API's history (`pr-history`), never from what the author says."""
    reasons = []
    verb = _title_verb(title)
    if verb in rule.get("verbs", ["Fix", "Rework", "Revert"]):
        reasons.append(f"its title says {verb}")
    failed = history.get("failed_earlier", [])
    if failed:
        reasons.append(f"{', '.join(failed[:4])} failed on an earlier commit of it")
    bug_labels = set(rule.get("bug_labels", ["bug"]))
    bugs = [c["number"] for c in history.get("closes", []) if bug_labels & set(c.get("labels", []))]
    if bugs:
        reasons.append(f"it closes {', '.join(f'#{n}' for n in bugs[:4])}, labelled {'/'.join(sorted(bug_labels))}")
    return reasons


_LESSON_LINK = re.compile(r"lessons/20\d\d-\d\d-\d\d-[\w.-]+\.md|maintainer-corrections")


def lessons_problems(conv: dict[str, Any], title: str, body: str, history: dict[str, Any] | None) -> list[str]:
    """Docs ship with the change (pull_requests.kit_docs, lessons, read_first), judged from the title, the description
    and the pull request's history (`pr-history`: failed earlier checks, the issues it closes and their labels)."""
    history = history or {}
    rules = conv["pull_requests"]
    problems: list[str] = []
    closes = history.get("closes", [])
    rule = rules.get("lessons")
    reasons = self_correction_reasons(rule, title, history) if rule else []
    if rule:
        label = rule.get("label", "Lessons:")
        value = _summary_value(conv, body, rule, "Lessons:")
        is_none = value is not None and value.lower().startswith("none")
        if value is not None and is_none and not _reasoned(value[4:]):
            problems.append(f"'{label} none' needs a reason in parentheses: '{label} none (why nothing went wrong)'")
        elif reasons and (value is None or is_none):
            problems.append(
                f"this pull request corrects earlier work ({'; '.join(reasons)}): link the lesson that records what "
                f"went wrong, in ## {rule.get('section', 'Summary')} as '{label} docs/lessons/<file>.md' (or a row of "
                f"the corrections page); '{label} none' is refused here")
        elif value is not None and not is_none and not _LESSON_LINK.search(value):
            problems.append(f"'{label}' links a lesson (docs/lessons/<yyyy-mm-dd>-<slug>.md) or a row of the "
                            f"corrections page, or reads '{label} none (reason)': {value!r}")
    kit = rules.get("kit_docs")
    if kit:
        label = kit.get("label", "Kit docs:")
        bug_labels = set(kit.get("bug_labels", ["bug"]))
        needed = _title_verb(title) in kit.get("verbs", ["Fix", "Rework"]) or any(
            bug_labels & set(c.get("labels", [])) for c in closes)
        value = _summary_value(conv, body, kit, "Kit docs:")
        repo = re.escape(kit.get("repo", "gdstudio"))
        link = re.compile(rf"https://github\.com/[\w.-]+/{repo}/pull/\d+|(?:[\w.-]+/)?{repo}#\d+")
        if value is None and needed:
            problems.append(f"a fix or rework documents the process in the kit, in the same task: add a line '{label} "
                            f"<the kit pull request>' to ## {kit.get('section', 'Summary')}, or '{label} none (reason)'")
        elif value is not None:
            if value.lower().startswith("none"):
                if not _reasoned(value[4:]):
                    problems.append(f"'{label} none' needs a reason in parentheses: '{label} none (why nothing needs "
                                    f"documenting)'")
            elif not link.search(value):
                problems.append(f"'{label}' names the kit pull request ({kit.get('repo', 'gdstudio')}#N or its URL), "
                                f"or reads '{label} none (reason)': {value!r}")
    first = rules.get("read_first")
    if first and closes:
        label = first.get("label", "Read first:")
        wanted = _areas_of_labels(first, {name for c in closes for name in c.get("labels", [])})
        value = _summary_value(conv, body, first, "Read first:")
        named = {a.lower() for a in re.split(r"[\s,;]+", value or "") if a}
        if value is None:
            hint = f" naming {', '.join(wanted)}" if wanted else ""
            problems.append(f"a pull request that closes an issue says which areas' checks the author read first: add "
                            f"'{label} <areas>'{hint} to ## {first.get('section', 'Summary')} (`gds lessons <area>`)")
        elif wanted and not set(wanted) <= named:
            problems.append(f"'{label}' must name the areas of the issue's labels; missing "
                            f"{', '.join(sorted(set(wanted) - named))} (the issue has "
                            f"{', '.join(sorted({n for c in closes for n in c.get('labels', []) if n.startswith('A-')}))})")
    return problems


def _areas_of_labels(rule: dict[str, Any], labels: set[str]) -> list[str]:
    """The glossary areas of some issue labels (docs/lessons/areas.toml `[labels]`), without `general`; empty when the
    repository has no areas file."""
    path = Path(rule.get("areas_file", "docs/lessons/areas.toml"))
    if not path.is_file():
        return []
    mapping = tomllib.loads(path.read_text(encoding="utf-8")).get("labels", {})
    found: list[str] = []
    for label in sorted(labels):
        found += [a for a in mapping.get(label, []) if a not in found and a != "general"]
    return found


def failed_checks(listing: str, watched: set[str]) -> set[str]:
    """The watched checks that really failed on one commit, from its check runs (`name<TAB>conclusion<TAB>suite`, one
    per line). A required-check job like `build-ok` runs `if: always()` and fails when a job it needs was cancelled,
    and a run is cancelled when a newer push starts one (`concurrency: cancel-in-progress`): that is no earlier work
    gone wrong. A failed check does not count when the other jobs of its own run (the same check suite) include a
    cancelled one and none that failed; a failure with no cancelled sibling, or beside a failed one, still counts."""
    rows = []
    for line in listing.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            rows.append((parts[0], parts[1], parts[2] if len(parts) > 2 else ""))
    failed: set[str] = set()
    for name, conclusion, suite in rows:
        if name not in watched or conclusion not in ("failure", "timed_out"):
            continue
        siblings = {c for n, c, s in rows if suite and s == suite and n != name}
        if "cancelled" in siblings and not siblings & {"failure", "timed_out"}:
            continue
        failed.add(name)
    return failed


def collect_history(conv: dict[str, Any], repo: str, number: int, run: Any = None) -> dict[str, Any]:
    """What GitHub knows about a pull request that its text does not say: the watched checks that failed on an earlier
    commit (pull_requests.lessons.history_checks, else merge.required_checks), and the issues it closes with their
    labels. `run` is `gh` (tests pass a fake)."""
    run = run or gh
    rule = conv["pull_requests"].get("lessons", {})
    watched = set(rule.get("history_checks", conv.get("merge", {}).get("required_checks", [])))
    shas = run("api", "--paginate", f"repos/{repo}/pulls/{number}/commits", "--jq", ".[].sha").split()
    failed: set[str] = set()
    for sha in shas[:-1][-20:]:  # every commit but the last (the one being judged), the newest twenty
        out = run("api", f"repos/{repo}/commits/{sha}/check-runs?per_page=100", "--jq",
                  r'.check_runs[] | [.name, .conclusion, (.check_suite.id | tostring)] | @tsv')
        failed |= failed_checks(out, watched)
    closes = []
    out = run("pr", "view", str(number), "-R", repo, "--json", "closingIssuesReferences", "--jq",
              r'.closingIssuesReferences[] | select(.repository.owner.login + "/" + .repository.name == "' + repo
              + r'") | .number')
    for issue in out.split():
        labels = run("api", f"repos/{repo}/issues/{issue}", "--jq", r'[.labels[].name] | join(",")').strip()
        closes.append({"number": int(issue), "labels": [x for x in labels.split(",") if x]})
    return {"failed_earlier": sorted(failed), "closes": closes}


def issue_area(conv: dict[str, Any], body: str) -> str:
    """The Area an issue form's body chose (`### Area` then the option), '' when absent or not an allowed option."""
    label = "Area"
    for form in conv.get("issues", {}).get("forms", {}).values():
        for spec in form.get("sections", {}).values():
            if isinstance(spec, dict) and spec.get("options_from") == "title_areas":
                label = spec["heading"]
    match = re.search(rf"^###\s+{re.escape(label)}\s*\n+\s*(\S+)\s*$", body, re.MULTILINE)
    value = match.group(1) if match else ""
    return value if value in area_options(conv) else ""


def ai_model_line(conv: dict[str, Any], body: str) -> str:
    """The description's model line (pull_requests.ai_use.model), '' when there is none."""
    ai = conv["pull_requests"].get("ai_use")
    if not ai:
        return ""
    sections = split_sections(body)
    return _field(_COMMENT.sub("", sections.get(ai["section"], "")), ai["model"]["label"])


# --------------------------------------------------------------------------------------------------------------------
# Commit messages: trailers and e-mail addresses (commits.trailers)
# --------------------------------------------------------------------------------------------------------------------

_TRAILER = re.compile(r"^([A-Za-z][A-Za-z0-9-]*):[ \t]+(.+)$")
_EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
_PERSON = re.compile(r"^(.+?)\s*<([^<>\s]+)>$")


def split_trailers(message: str) -> list[tuple[str, str]]:
    """The trailers of a commit message: the last paragraph, when every line of it is `Key: value`."""
    paragraphs = [p for p in re.split(r"\n\s*\n", message.strip()) if p.strip()]
    if len(paragraphs) < 2:
        return []
    lines = paragraphs[-1].strip().splitlines()
    matches = [_TRAILER.match(ln.strip()) for ln in lines]
    return [(m.group(1), m.group(2).strip()) for m in matches if m] if all(matches) else []


def trailer_models(conv: dict[str, Any], message: str) -> list[str]:
    """The model names an AI co-author trailer of `message` gives."""
    rule = conv["commits"].get("trailers")
    if not rule:
        return []
    key = rule["ai_co_author"].get("key", "Co-Authored-By").lower()
    names = []
    for k, v in split_trailers(message):
        person = _PERSON.match(v)
        if k.lower() == key and person:
            names.append(person.group(1).strip())
    return names


#: What git writes under the message in the editor (`git commit` without -m/-F/--no-edit): its first line, then the
#: `--verbose` diff after the scissors line. Everything from there on is never part of the commit.
_EDITOR_HELP = re.compile(r"^#\s+(?:Please enter the commit message|-{10,} >8 -{10,})", re.MULTILINE)
_SCISSORS = re.compile(r"^# -{10,} >8 -{10,}")
_COMMENT_LINE = re.compile(r"^#", re.MULTILINE)


def stored_message(raw: str) -> str:
    """The message a commit will have, from the file a `commit-msg` hook is given (before git's cleanup).

    CI judges the stored message, so this is the only place the two can differ, and it is decided by how git was
    run. In the editor git adds its help text (`# Please enter the commit message...`) and strips every `#` line, so
    those lines are not part of the commit. With `-m`, `-F` or `--no-edit` git keeps `#` lines as they are (its
    cleanup is `whitespace` then, not `strip`), and a `# Conflicts:` paragraph that `git merge` left in MERGE_MSG
    becomes part of the commit, after the trailer. The old hook dropped every `#` line always, so it passed the
    message that `pr-rules` then refused (deadnight #503, lesson 2026-11-02-a-merge-committed-after-conflicts).
    `--cleanup=strip -F` is judged as kept (the safe side): write no `#` lines, or pass `--cleanup=whitespace`."""
    if not _EDITOR_HELP.search(raw):
        return raw
    lines = raw.splitlines()
    for i, ln in enumerate(lines):
        if _SCISSORS.match(ln):  # `commit --verbose` puts the diff under the scissors line, not '#'-prefixed
            lines = lines[:i]
            break
    return "\n".join(ln for ln in lines if not ln.startswith("#"))


def commit_problems(conv: dict[str, Any], message: str) -> list[str]:
    """Check one commit message, as stored, against commits.trailers; return what is wrong. The one function behind
    the `commit-msg` hook, the `pre-push` hook and the `commits` check of CI."""
    rule = conv["commits"].get("trailers")
    if not rule:
        return []
    ai = rule["ai_co_author"]
    key = ai.get("key", "Co-Authored-By")
    noreply = {a.lower() for a in ai["noreply"]}
    problems: list[str] = []
    paragraphs = [p for p in re.split(r"\n\s*\n", message.strip()) if p.strip()]
    if len(paragraphs) > 1 and all(_COMMENT_LINE.match(ln) for ln in paragraphs[-1].splitlines() if ln.strip()):
        problems.append("the message ends with a paragraph of '#' lines (git leaves a '# Conflicts:' list there when "
                        "a merge is committed with --no-edit), so the trailer is not the last paragraph: reword "
                        "the commit with `git commit --amend --cleanup=strip -F <message file>`")
    allowed_emails: set[str] = set()
    for k, v in split_trailers(message):
        if k.lower() == key.lower():
            person = _PERSON.match(v)
            if not person or person.group(2).lower() not in noreply:
                problems.append(f"'{k}: {v}' must read '{key}: {ai.get('value', '<model name> <noreply address>')}' "
                                f"with one of: {', '.join(sorted(noreply))}")
            else:
                allowed_emails.add(person.group(2).lower())
        elif rule.get("only_ai_co_author", False):
            problems.append(f"trailer '{k}' is not allowed; the only trailer is '{key}'")
    if rule.get("other_emails", True) is False:
        for email in _EMAIL.findall(message):
            if email.lower() not in allowed_emails:
                problems.append(f"an e-mail address ({email}) appears in the message; none may, apart from the "
                                f"{key} trailer's noreply address")
    return problems


def commits_problems(conv: dict[str, Any], commits: list[tuple[str, str]], body: str | None) -> list[str]:
    """Check every (sha, message) of a pull request, and that its model line names each trailer's model."""
    problems = [f"{sha[:10]}: {p}" for sha, msg in commits for p in commit_problems(conv, msg)]
    ai = conv["pull_requests"].get("ai_use") or {}
    if body is not None and ai.get("model", {}).get("names_trailer_models"):
        line = ai_model_line(conv, body).lower()
        for name in sorted({n for _, msg in commits for n in trailer_models(conv, msg)}):
            if name.lower() not in line:
                problems.append(f"a commit names the model {name!r} in its trailer, but the description's "
                                f"'{ai['model']['label']}' line does not")
    return problems


def read_commits(source: str) -> list[tuple[str, str]]:
    """(sha, message) pairs from GitHub's pull request commits JSON (a file, or - for stdin), or from `git log` when
    `source` is `git:<range>`."""
    if source.startswith("git:"):
        out = subprocess.run(["git", "log", "--format=%H%x00%B%x1e", *source[4:].split()], capture_output=True, text=True,
                             encoding="utf-8", check=True).stdout
        pairs = [chunk.strip("\n").split("\x00", 1) for chunk in out.split("\x1e") if chunk.strip()]
        return [(sha, msg) for sha, msg in pairs]
    data = json.loads(_read(source) or "[]")
    if data and isinstance(data[0], list):  # gh api --paginate --slurp gives one list per page
        data = [item for page in data for item in page]
    return [(item["sha"], item["commit"]["message"]) for item in data]


# --------------------------------------------------------------------------------------------------------------------
# Files that must hold only a pointer, and changes a maintainer merges by hand
# --------------------------------------------------------------------------------------------------------------------


def pointer_problems(conv: dict[str, Any], root: Path = Path(".")) -> list[str]:
    """Each pointer file (paths.pointer_files) holds only its pointer, such as CLAUDE.md holding `@AGENTS.md`."""
    rule = conv.get("paths", {}).get("pointer_files")
    if not rule:
        return []
    problems = []
    for name in rule["files"]:
        path = root / name
        if not path.exists():
            continue
        raw = path.read_bytes()
        lines = [ln.strip() for ln in raw.decode("utf-8", "replace").splitlines()]
        lines = [ln for ln in lines if ln and not ln.startswith("#")]
        if lines != [rule["content"]]:
            problems.append(f"{name} must hold only '{rule['content']}' (a heading line is allowed); put the rest in "
                            f"the file it points to")
        if len(raw) > rule.get("max_bytes", 400):
            problems.append(f"{name} is {len(raw)} bytes; at most {rule.get('max_bytes', 400)}")
    return problems


def manual_matches(conv: dict[str, Any], changed: list[str]) -> list[str]:
    """The changed paths under merge.manual_paths: a pull request touching one is merged by a maintainer by hand."""
    return [p for p in changed if _under(p, conv.get("merge", {}).get("manual_paths", []))]


def _field(text: str, label: str) -> str:
    """The value after a `**Label**` (or `Label`) in a section, '' when absent."""
    bare = label.rstrip(":")
    match = re.search(rf"\*\*{re.escape(bare)}:?\*\*:?[ \t]*(.*)|^[ \t]*[-*]?[ \t]*{re.escape(label)}[ \t]*(.*)", text,
                      re.MULTILINE)
    if not match:
        return ""
    return (match.group(1) or match.group(2) or "").strip()


def _under(path: str, prefixes: list[str]) -> bool:
    """True when `path` is under one of the folder prefixes (or equals a file prefix)."""
    return any(path == p or (p.endswith("/") and path.startswith(p)) for p in prefixes)


def docs_problems(conv: dict[str, Any], body: str, changed: list[str]) -> list[str]:
    """A change to code needs a change to docs, or the description's escape line (pull_requests.docs_none)."""
    rule = conv["pull_requests"].get("docs_none")
    if not rule:
        return []
    paths = conv.get("paths", {})
    code, docs = paths.get(rule["when_changed"], []), paths.get(rule["unless_changed"], [])
    if not any(_under(p, code) for p in changed) or any(_under(p, docs) for p in changed):
        return []
    if any(ln.strip() == rule["line"] for ln in _COMMENT.sub("", body).splitlines()):
        return []
    return [f"code changed without a docs change; update the docs or add a line '{rule['line']}'"]


# --------------------------------------------------------------------------------------------------------------------
# Rendering the files that follow the conventions (so they cannot drift)
# --------------------------------------------------------------------------------------------------------------------


def render_template(conv: dict[str, Any]) -> str:
    """The pull request template: the sections in order, with their guidance as comments."""
    rule = conv["pull_requests"]
    guidance = rule.get("guidance", {})
    out = ["<!-- markdownlint-disable-file MD041 -- a pull request body starts at the second heading level -->"]
    for name in rule["sections"]:
        out.append(f"## {name}\n")
        if name in guidance:
            out.append(f"<!-- {guidance[name].strip()} -->\n")
        if name == rule.get("checklist", {}).get("section"):
            out.append("- [x] ...\n")
        elif rule.get("ai_use") and name == rule["ai_use"]["section"]:
            ai = rule["ai_use"]
            out.append(f"- **{ai['written_by']['label']}** <!-- {' / '.join(ai['written_by']['choices'])} -->")
            out.append(f"- **{ai['model']['label']}** <!-- the model that wrote them; {ai['model']['none']} when a person did -->\n")
        elif name == rule.get("issues_affected", {}).get("section"):
            out.append("- ...\n")
        elif name == rule.get("screenshots", {}).get("section") and rule["screenshots"].get("before_after"):
            pair = rule["screenshots"]["before_after"]
            out.append(f"- **{pair.get('before', 'Before:')}** ...")
            out.append(f"- **{pair.get('after', 'After:')}** ...\n")
        elif name in rule.get("filled", []):
            out.append("- ...\n")
    return "\n".join(out).rstrip() + "\n"


def render_form(conv: dict[str, Any], name: str) -> str:
    """One issue form as GitHub's YAML, from issues.forms.<name>."""
    form = conv["issues"]["forms"][name]
    body: list[dict[str, Any]] = []
    if form.get("intro"):
        body.append({"type": "markdown", "attributes": {"value": form["intro"].strip() + "\n"}})
    for key, spec in form["sections"].items():
        label, required = (spec[0], spec[1]) if isinstance(spec, list) else (spec["heading"], spec.get("required", False))
        kind = "textarea" if isinstance(spec, list) else spec.get("type", "textarea")
        entry: dict[str, Any] = {"type": kind, "id": key, "attributes": {"label": label}}
        if isinstance(spec, dict):
            if spec.get("description"):
                entry["attributes"]["description"] = spec["description"]
            if spec.get("placeholder"):
                entry["attributes"]["placeholder"] = spec["placeholder"]
            if kind == "dropdown":
                entry["attributes"]["options"] = (area_options(conv) if spec.get("options_from") == "title_areas"
                                                  else spec["options"])
        if required:
            entry["validations"] = {"required": True}
        body.append(entry)
    doc = {"name": form.get("name", name.capitalize()), "description": form.get("description", f"File a {name}"),
           "title": form["title_prefix"], "labels": form["labels"], "body": body}
    header = "# Generated from .github/conventions.yml by `groundwork.py render`; edit the conventions, not this file.\n"
    return header + yaml.safe_dump(doc, sort_keys=False, width=110, allow_unicode=True)


def render_config(conv: dict[str, Any]) -> str:
    """ISSUE_TEMPLATE/config.yml: whether a blank issue is allowed."""
    blank = str(bool(conv["issues"].get("blank_issues", False))).lower()
    return f"# Generated from .github/conventions.yml by `groundwork.py render`.\nblank_issues_enabled: {blank}\n"


def rendered_files(conv: dict[str, Any]) -> dict[str, str]:
    """Every file `render` owns, by repository-relative path."""
    files = {
        conv["pull_requests"].get("template", ".github/pull_request_template.md"): render_template(conv),
        ".github/ISSUE_TEMPLATE/config.yml": render_config(conv),
    }
    for name, form in conv["issues"].get("forms", {}).items():
        files[form.get("file", f".github/ISSUE_TEMPLATE/{name}.yml")] = render_form(conv, name)
    return files


# Generated blocks inside hand-written files (paths.blocks_in), such as AGENTS.md:
#   <!-- conventions:begin commit-rules -->
#   ...written by `render`...
#   <!-- conventions:end -->
_BLOCK = re.compile(r"(<!-- conventions:begin ([a-z-]+) -->\n)(.*?)(<!-- conventions:end -->)", re.DOTALL)


def _wrap(text: str, width: int = 116, indent: str = "  ") -> list[str]:
    """Wrap a bullet's text to `width`, continuation lines indented."""
    words, lines, line = text.split(), [], ""
    for word in words:
        if line and len(line) + 1 + len(word) > width:
            lines.append(line)
            line = indent + word
        else:
            line = f"{line} {word}" if line else word
    return lines + [line] if line else lines


def render_block(conv: dict[str, Any], name: str) -> str:
    """The text of one generated block, by name; ConventionsError for a name render does not know."""
    title = conv["commits"]["title"]
    bullets: list[str] = []
    if name == "commit-rules":
        bullets.append(
            f"Title `{title.get('form', 'area: Verb the rest')}`, at most {title.get('max_length', 72)} characters, "
            f"present tense{'' if title.get('trailing_period') else ', no trailing period'}. "
            f"Verbs: {', '.join(title['verbs'])}. Areas: {', '.join(f'`{a}`' for a in title['areas'])}."
            + (f" A breaking change ends the title with `{title['breaking_suffix']}`." if title.get("breaking_suffix") else ""))
        trailers = conv["commits"].get("trailers")
        if trailers:
            ai = trailers["ai_co_author"]
            text = (f"An agent ends the message with `{ai.get('key', 'Co-Authored-By')}: "
                    f"{ai.get('value', '<model name> <noreply address>')}` (one of: "
                    f"{', '.join(f'`{a}`' for a in ai['noreply'])})")
            text += " and no other trailer" if trailers.get("only_ai_co_author") else ""
            text += ". No other e-mail address appears in a message." if trailers.get("other_emails") is False else "."
            bullets.append(text)
    elif name == "maintainer-decisions":
        decisions = conv["repo"].get("maintainer_decisions", [])
        bullets.append("**Maintainer decisions** are never an agent's: it stops and reports instead of acting. They are: "
                       + "; ".join(decisions) + ".")
    elif name == "manual-paths":
        paths = conv.get("merge", {}).get("manual_paths", [])
        bullets.append("A pull request that changes any of these is merged by a maintainer by hand, never by auto-merge: "
                       + ", ".join(f"`{p}`" for p in paths) + ".")
    else:
        raise ConventionsError(f"unknown generated block {name!r}; known: commit-rules, maintainer-decisions, manual-paths")
    return "".join("\n".join(["- " + _wrap(b)[0], *_wrap(b)[1:]]) + "\n" for b in bullets)


def render_blocks_in(conv: dict[str, Any], text: str) -> str:
    """`text` with every generated block rewritten from the conventions."""
    return _BLOCK.sub(lambda m: m.group(1) + render_block(conv, m.group(2)) + m.group(4), text)


# --------------------------------------------------------------------------------------------------------------------
# GitHub: labels, settings, the ruleset
# --------------------------------------------------------------------------------------------------------------------


def gh(*args: str, stdin: str | None = None, check: bool = True) -> str:
    """Run `gh` and return its standard output."""
    result = subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True, encoding="utf-8")
    if check and result.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def label_diff(conv: dict[str, Any], repo: str | None) -> tuple[list[dict], list[dict], list[str]]:
    """Compare labels.list with the repository: (to create, to change, extra names the repository has)."""
    repo_args = ["-R", repo] if repo else []
    have = {item["name"]: item for item in json.loads(gh("label", "list", "--json", "name,color,description", "-L", "500", *repo_args))}
    create: list[dict] = []
    change: list[dict] = []
    wanted = {item["name"]: item for item in all_labels(conv)}
    for name, item in wanted.items():
        if name not in have:
            create.append(item)
        elif have[name]["color"].lower() != str(item["color"]).lower() or have[name].get("description", "") != item.get("description", ""):
            change.append(item)
    return create, change, sorted(set(have) - set(wanted))


def settings_wanted(conv: dict[str, Any]) -> dict[str, Any]:
    """The repository settings that the merge section asks for, as GitHub's API names them."""
    merge = conv["merge"]
    methods = merge.get("methods", ["squash"])
    return {
        "allow_squash_merge": "squash" in methods,
        "allow_merge_commit": "merge" in methods,
        "allow_rebase_merge": "rebase" in methods,
        "allow_auto_merge": bool(merge.get("auto_merge", False)),
        "delete_branch_on_merge": bool(merge.get("delete_branch_on_merge", True)),
        "squash_merge_commit_title": merge.get("squash_title", "PR_TITLE"),
        "squash_merge_commit_message": merge.get("squash_message", "PR_BODY"),
    }


def ruleset_wanted(conv: dict[str, Any]) -> dict[str, Any]:
    """The branch ruleset for the default branch, as the rulesets API takes it."""
    merge = conv["merge"]
    rules: list[dict[str, Any]] = [
        {"type": "deletion"},
        {"type": "non_fast_forward"},
        {"type": "pull_request", "parameters": {
            "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": False,
            "require_code_owner_review": False, "require_last_push_approval": False,
            "required_review_thread_resolution": False,
            "allowed_merge_methods": [m for m in merge.get("methods", ["squash"])]}},
    ]
    if merge.get("linear_history", True):
        rules.append({"type": "required_linear_history"})
    hold = merge.get("hold")
    if merge.get("required_checks") or hold:
        checks: list[dict[str, Any]] = [{"context": c} for c in merge.get("required_checks", [])]
        if hold:  # from one app only: anyone with write access can post a commit status of any name
            checks.append({"context": hold["check"], "integration_id": hold["app_id"]})
        rules.append({"type": "required_status_checks", "parameters": {
            "strict_required_status_checks_policy": bool(merge.get("up_to_date_required", False)),
            "required_status_checks": checks}})
    return {"name": merge.get("ruleset_name", "Main"), "target": "branch", "enforcement": "active",
            "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}}, "rules": rules,
            "bypass_actors": []}


def normalise_ruleset(rs: dict[str, Any]) -> dict[str, Any]:
    """Reduce a ruleset (ours or GitHub's reply) to the fields that matter, for comparison."""
    rules = {}
    for rule in rs.get("rules", []):
        params = rule.get("parameters", {})
        if rule["type"] == "required_status_checks":
            params = {"strict": params.get("strict_required_status_checks_policy", False),
                      "contexts": sorted((c["context"], c.get("integration_id") or 0)
                                         for c in params.get("required_status_checks", []))}
        elif rule["type"] == "pull_request":
            params = {"methods": sorted(params.get("allowed_merge_methods", []))}
        else:
            params = {}
        rules[rule["type"]] = params
    return {"name": rs["name"], "enforcement": rs.get("enforcement"), "rules": rules}


def current_repo() -> str:
    """owner/name of the repository gh is pointed at."""
    return json.loads(gh("repo", "view", "--json", "nameWithOwner"))["nameWithOwner"]


def ruleset_state(conv: dict[str, Any], repo: str) -> tuple[dict | None, dict]:
    """(the existing ruleset with our name or None, the wanted one)."""
    wanted = ruleset_wanted(conv)
    for item in json.loads(gh("api", f"repos/{repo}/rulesets") or "[]"):
        if item["name"] == wanted["name"]:
            return json.loads(gh("api", f"repos/{repo}/rulesets/{item['id']}")), wanted
    return None, wanted


def settings_drift(conv: dict[str, Any], repo: str) -> dict[str, tuple[Any, Any]]:
    """Settings that differ: name -> (now, wanted)."""
    now = json.loads(gh("api", f"repos/{repo}"))
    return {k: (now.get(k), v) for k, v in settings_wanted(conv).items() if now.get(k) != v}


# --------------------------------------------------------------------------------------------------------------------
# Hygiene: the weekly sweep
# --------------------------------------------------------------------------------------------------------------------


def _age_days(stamp: str, now: dt.datetime) -> float:
    return (now - dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))).total_seconds() / 86400


def hygiene_findings(conv: dict[str, Any], repo: str | None, now: dt.datetime) -> list[str]:
    """Findings about open issues and pull requests, as Markdown bullets."""
    repo_args = ["-R", repo] if repo else []
    issues = json.loads(gh("issue", "list", "--state", "open", "-L", "500", "--json", "number,title,labels,updatedAt", *repo_args))
    prs = json.loads(gh("pr", "list", "--state", "open", "-L", "200", "--json", "number,title,updatedAt,body", *repo_args))
    fam = conv.get("labels", {}).get("families", {})
    thresholds = conv.get("hygiene", {}).get("thresholds", {})
    findings: list[str] = []

    def members(names: list[str], family: str) -> list[str]:
        spec = fam.get(family, {})
        prefix = spec.get("prefix", "")
        listed = spec.get("names", [])
        return [n for n in names if (prefix and n.startswith(prefix)) or n in listed]

    wanted = conv.get("issues", {}).get("labels", {})
    for issue in issues:
        names = [lab["name"] for lab in issue["labels"]]
        ref = f"#{issue['number']} {issue['title']}"
        for family, mode in wanted.items():
            if family not in fam or mode.startswith("exactly-one-after"):
                continue
            count = len(members(names, family))
            if mode == "exactly-one" and count != 1:
                findings.append(f"- {ref}: {count} {family} labels, expected exactly one")
            elif mode == "at-least-one" and count < 1:
                findings.append(f"- {ref}: no {family} label")
        age = _age_days(issue["updatedAt"], now)
        status = members(names, "status")
        limits = {"S-needs-triage": thresholds.get("needs_triage_days"), "S-needs-info": thresholds.get("needs_info_days"),
                  "S-in-progress": thresholds.get("in_progress_idle_days")}
        for label in status:
            if limits.get(label) and age > limits[label]:
                findings.append(f"- {ref}: {label} for {int(age)} days (limit {limits[label]})")
    limit = thresholds.get("pull_request_idle_days")
    for pr in prs:
        ref = f"#{pr['number']} {pr['title']}"
        for problem in title_problems(conv, pr["title"]):
            findings.append(f"- {ref}: title {problem}")
        for problem in body_problems(conv, pr.get("body") or ""):
            findings.append(f"- {ref}: description: {problem}")
        if limit and _age_days(pr["updatedAt"], now) > limit:
            findings.append(f"- {ref}: no activity for {int(_age_days(pr['updatedAt'], now))} days (limit {limit})")
    return findings


def post_report(conv: dict[str, Any], repo: str | None, text: str) -> str:
    """Edit the one report comment on the report issue (creating the issue and the comment when missing)."""
    repo_args = ["-R", repo] if repo else []
    spec = conv.get("hygiene", {}).get("report_issue", {"title": "Repo hygiene", "labels": []})
    found = json.loads(gh("issue", "list", "--state", "open", "--search", f'"{spec["title"]}" in:title', "--json",
                          "number,title", *repo_args))
    number = next((i["number"] for i in found if i["title"] == spec["title"]), None)
    if number is None:
        label_args = [a for lab in spec.get("labels", []) for a in ("--label", lab)]
        url = gh("issue", "create", "--title", spec["title"], "--body", "The weekly hygiene sweep keeps one comment here.",
                 *label_args, *repo_args).strip()
        number = int(url.rsplit("/", 1)[1])
    target = repo or current_repo()
    comments = json.loads(gh("api", f"repos/{target}/issues/{number}/comments", "--paginate"))
    marker = f"<!-- {MARKER} -->"
    body = f"{marker}\n{text}"
    for comment in comments:
        if comment["body"].startswith(marker):
            gh("api", "--method", "PATCH", f"repos/{target}/issues/comments/{comment['id']}", "-f", f"body={body}")
            return f"updated the report on #{number}"
    gh("api", "--method", "POST", f"repos/{target}/issues/{number}/comments", "-f", f"body={body}")
    return f"posted the report on #{number}"


# --------------------------------------------------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------------------------------------------------


def _read(source: str) -> str:
    """Text from stdin when source is '-', else from a file."""
    return sys.stdin.read() if source == "-" else Path(source).read_text(encoding="utf-8-sig")


def _report(problems: list[str], what: str) -> int:
    if problems:
        print(f"{what}: refused", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print(f"{what}: ok")
    return 0


def cmd_validate(conv: dict[str, Any], args: argparse.Namespace) -> int:
    return _report([], "conventions")  # load() already refused a bad file


#: Commit titles git or a tool writes, which the squash replaces anyway (a commit-msg hook lets them pass).
_TOOL_TITLES = re.compile(r"^(?:fixup!|squash!|amend!|Merge |Revert \")")


def cmd_check_title(conv: dict[str, Any], args: argparse.Namespace) -> int:
    lines = _read(args.title).splitlines()
    if args.commit_msg:  # a commit message file: drop git's comment lines, let tool-written titles pass
        lines = [ln for ln in lines if not ln.startswith("#") and ln.strip()]
        if lines and _TOOL_TITLES.match(lines[0]):
            return _report([], "title")
    return _report(title_problems(conv, lines[0] if lines else ""), "title")


def cmd_check_commits(conv: dict[str, Any], args: argparse.Namespace) -> int:
    body = _read(args.body) if args.body else None
    return _report(commits_problems(conv, read_commits(args.commits), body), "commits")


def cmd_check_message(conv: dict[str, Any], args: argparse.Namespace) -> int:
    """One commit message (a commit-msg hook's file): its trailers and e-mail addresses."""
    return _report(commit_problems(conv, stored_message(_read(args.message))), "commit message")


def _has_ref(name: str) -> bool:
    """True when git knows the ref `name`."""
    return subprocess.run(["git", "rev-parse", "--verify", "--quiet", name], capture_output=True).returncode == 0


def cmd_check_push(conv: dict[str, Any], args: argparse.Namespace) -> int:
    """The `pre-push` hook: every commit about to leave the machine, merges included, judged as CI will judge it. The
    range comes from pre-commit's environment (`PRE_COMMIT_FROM_REF..PRE_COMMIT_TO_REF`) or `--range`."""
    to_ref = os.environ.get("PRE_COMMIT_TO_REF", "")
    from_ref = os.environ.get("PRE_COMMIT_FROM_REF", "")
    rng = args.range or (f"{from_ref}..{to_ref}" if from_ref and to_ref else f"{to_ref} --not --remotes")
    if not args.range and from_ref and _has_ref("origin/main"):
        rng += " --not origin/main"  # the commits a merge of main brings are main's, already judged and squashed
    if not args.range and (not to_ref or set(to_ref) == {"0"}):  # a branch deletion, or git gave no range
        return _report([], "push")
    problems = []
    for sha, msg in read_commits(f"git:{rng}"):
        lines = [ln for ln in msg.splitlines() if ln.strip()]
        found = commit_problems(conv, msg)
        if lines and not _TOOL_TITLES.match(lines[0]):
            found += title_problems(conv, lines[0])
        problems += [f"{sha[:10]} {lines[0] if lines else ''!r}: {p}" for p in found]
    if problems:
        print("these commits stay on this machine, so no force push is needed: reword the last one with "
              "`git commit --amend --cleanup=strip -F <message file>`; for an older one, `git reset --soft <base>` "
              "and commit again with a clean message.", file=sys.stderr)
    return _report(problems, "push")


def cmd_check_files(conv: dict[str, Any], args: argparse.Namespace) -> int:
    return _report(pointer_problems(conv), "files")


def cmd_needs_maintainer(conv: dict[str, Any], args: argparse.Namespace) -> int:
    """Exit 1 (and list them) when a changed path is a manual path; tools refuse auto-merge then."""
    matches = manual_matches(conv, Path(args.changed).read_text(encoding="utf-8").split())
    for path in matches:
        print(path)
    print("a maintainer merges this by hand" if matches else "auto-merge allowed", file=sys.stderr)
    return 1 if matches else 0


def cmd_check_body(conv: dict[str, Any], args: argparse.Namespace) -> int:
    body = _read(args.body)
    problems = body_problems(conv, body)
    if args.title:
        lines = _read(args.title).splitlines()
        title = lines[0] if lines else ""
        problems += screenshot_problems(conv, title, body)
        problems += failed_first_problems(conv, title, body)
        history = json.loads(_read(args.history)) if args.history else {}
        if history.get("unavailable"):
            print("note: the pull request's history could not be read; the title alone is judged", file=sys.stderr)
        problems += lessons_problems(conv, title, body, history)
    return _report(problems, "description")


def cmd_pr_history(conv: dict[str, Any], args: argparse.Namespace) -> int:
    """Print what the API knows of a pull request (failed earlier checks, closed issues and their labels) as JSON, for
    `check-body --history`. When GitHub cannot be asked it prints {"unavailable": true}: a check that cannot look judges
    from the title alone instead of failing the pull request."""
    try:
        history = collect_history(conv, args.repo, args.number)
    except RuntimeError as err:
        print(f"pr-history: {err}", file=sys.stderr)
        history = {"unavailable": True}
    print(json.dumps(history))
    return 0


def cmd_issue_area(conv: dict[str, Any], args: argparse.Namespace) -> int:
    """Print the area label an issue form's body chose (nothing when none); the issue-area workflow applies it."""
    area = issue_area(conv, _read(args.body))
    if area:
        print(area)
    return 0


def cmd_check_docs(conv: dict[str, Any], args: argparse.Namespace) -> int:
    changed = Path(args.changed).read_text(encoding="utf-8").split()
    return _report(docs_problems(conv, _read(args.body), changed), "docs")


def cmd_render(conv: dict[str, Any], args: argparse.Namespace) -> int:
    drift: list[str] = []
    files = rendered_files(conv)
    for name in conv.get("paths", {}).get("blocks_in", []):
        if Path(name).exists():
            files[name] = render_blocks_in(conv, Path(name).read_text(encoding="utf-8"))
    for path, text in files.items():
        target = Path(path)
        if args.check:
            if not target.exists() or target.read_text(encoding="utf-8") != text:
                drift.append(f"{path} differs from the conventions (run `groundwork.py render`)")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8", newline="\n")
            print(f"wrote {path}")
    return _report(drift, "rendered files") if args.check else 0


def cmd_labels(conv: dict[str, Any], args: argparse.Namespace) -> int:
    create, change, extra = label_diff(conv, args.repo)
    for item in create + change:
        verb = "create" if item in create else "change"
        print(f"{verb} {item['name']}")
        if args.apply:
            gh("label", "create", item["name"], "--color", str(item["color"]), "--description", item.get("description", ""),
               "--force", *(["-R", args.repo] if args.repo else []))
    for name in extra:
        print(f"extra label (kept{'; deleted' if args.prune and args.apply else ''}): {name}")
        if args.prune and args.apply:
            gh("label", "delete", name, "--yes", *(["-R", args.repo] if args.repo else []))
    return 0 if args.apply or not (create or change) else 1


def cmd_settings(conv: dict[str, Any], args: argparse.Namespace) -> int:
    repo = args.repo or current_repo()
    drift = settings_drift(conv, repo)
    for key, (now, want) in drift.items():
        print(f"{key}: {now!r} -> {want!r}")
    if args.apply and drift:
        fields = [a for k, (_, v) in drift.items() for a in ("-F" if isinstance(v, bool) else "-f", f"{k}={str(v).lower() if isinstance(v, bool) else v}")]
        gh("api", "--method", "PATCH", f"repos/{repo}", *fields)
        print("applied")
        return 0
    return 1 if drift else 0


def cmd_ruleset(conv: dict[str, Any], args: argparse.Namespace) -> int:
    repo = args.repo or current_repo()
    existing, wanted = ruleset_state(conv, repo)
    if args.print:
        print(json.dumps(wanted, indent=2))
        return 0
    same = existing is not None and normalise_ruleset(existing) == normalise_ruleset(wanted)
    print("ruleset: in sync" if same else f"ruleset: {'differs' if existing else 'missing'}")
    if not same and args.apply:
        method, url = ("PUT", f"repos/{repo}/rulesets/{existing['id']}") if existing else ("POST", f"repos/{repo}/rulesets")
        gh("api", "--method", method, url, "--input", "-", stdin=json.dumps(wanted))
        print("applied")
        return 0
    return 0 if same else 1


def cmd_hygiene(conv: dict[str, Any], args: argparse.Namespace) -> int:
    findings = hygiene_findings(conv, args.repo, dt.datetime.now(dt.timezone.utc))
    text = "\n".join(findings) if findings else "No findings."
    print(text)
    if args.apply:
        print(post_report(conv, args.repo, text))
    return 0  # a sweep reports; it never fails a build


def cmd_check(conv: dict[str, Any], args: argparse.Namespace) -> int:
    """Everything at once: the files, then (unless --offline) the labels, settings and ruleset."""
    status = cmd_render(conv, argparse.Namespace(check=True))
    status |= cmd_check_files(conv, args)
    if not args.offline:
        repo = args.repo or current_repo()
        status |= cmd_labels(conv, argparse.Namespace(repo=repo, apply=False, prune=False))
        status |= cmd_settings(conv, argparse.Namespace(repo=repo, apply=False))
        status |= cmd_ruleset(conv, argparse.Namespace(repo=repo, apply=False, print=False))
    print("drift found" if status else "no drift")
    return 1 if status else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--conventions", default=str(CONVENTIONS), help="path to conventions.yml")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate", help="check that the conventions file is well formed").set_defaults(run=cmd_validate)
    p = sub.add_parser("check-title", help="check a title (a file, or - for stdin)")
    p.add_argument("title")
    p.add_argument("--commit-msg", action="store_true", help="the file is a commit message (a commit-msg hook)")
    p.set_defaults(run=cmd_check_title)
    p = sub.add_parser("check-commits", help="check commit trailers and e-mail addresses (commits.trailers)")
    p.add_argument("--commits", required=True,
                   help="GitHub's pull request commits JSON (a file, or - for stdin), or git:<range> for git log")
    p.add_argument("--body", help="the description, to check its model line names each trailer's model")
    p.set_defaults(run=cmd_check_commits)
    p = sub.add_parser("check-message", help="check one commit message's trailers (a file, or - for stdin)")
    p.add_argument("message")
    p.set_defaults(run=cmd_check_message)
    p = sub.add_parser("check-push", help="pre-push hook: check the title and trailers of every commit being pushed")
    p.add_argument("--range", help="a git revision range (default: pre-commit's PRE_COMMIT_FROM_REF..TO_REF)")
    p.set_defaults(run=cmd_check_push)
    sub.add_parser("check-files", help="pointer files hold only their pointer (paths.pointer_files)").set_defaults(
        run=cmd_check_files)
    p = sub.add_parser("needs-maintainer", help="exit 1 when a changed path is a manual path (merge.manual_paths)")
    p.add_argument("--changed", required=True, help="a file listing the changed paths")
    p.set_defaults(run=cmd_needs_maintainer)
    p = sub.add_parser("check-body", help="check a pull request description")
    p.add_argument("--body", required=True, help="a file, or - for stdin")
    p.add_argument("--title", help="the title (a file): enables the screenshots, failed-first and lessons rules")
    p.add_argument("--history", help="the output of pr-history (a file): lets the lessons rules see failed checks")
    p.set_defaults(run=cmd_check_body)
    p = sub.add_parser("pr-history", help="print a pull request's failed earlier checks and closed issues as JSON")
    p.add_argument("--repo", required=True, help="owner/name")
    p.add_argument("--number", required=True, type=int, help="the pull request number")
    p.set_defaults(run=cmd_pr_history)
    p = sub.add_parser("issue-area", help="print the area label an issue form's body chose")
    p.add_argument("--body", required=True, help="the issue body: a file, or - for stdin")
    p.set_defaults(run=cmd_issue_area)
    p = sub.add_parser("check-docs", help="a change to code needs a change to docs, or the escape line")
    p.add_argument("--body", required=True, help="the description: a file, or - for stdin")
    p.add_argument("--changed", required=True, help="a file listing the changed paths")
    p.set_defaults(run=cmd_check_docs)
    p = sub.add_parser("render", help="write (or with --check, compare) the template, issue forms and blocks")
    p.add_argument("--check", action="store_true"); p.set_defaults(run=cmd_render)
    for name, fn, helptext in (("labels", cmd_labels, "compare or sync the labels"),
                               ("settings", cmd_settings, "compare or apply the merge settings"),
                               ("ruleset", cmd_ruleset, "compare or apply the branch ruleset"),
                               ("hygiene", cmd_hygiene, "report stale or malformed issues and pull requests"),
                               ("check", cmd_check, "report drift between the repository and the conventions")):
        p = sub.add_parser(name, help=helptext)
        p.add_argument("-R", "--repo", help="owner/name (default: the current repository)")
        if name != "check":
            p.add_argument("--apply", action="store_true", help="change GitHub (otherwise only report)")
        if name == "labels":
            p.add_argument("--prune", action="store_true", help="with --apply, delete labels the conventions lack")
        if name == "ruleset":
            p.add_argument("--print", action="store_true", help="print the wanted ruleset JSON")
        if name == "check":
            p.add_argument("--offline", action="store_true", help="skip GitHub")
        p.set_defaults(run=fn)
    return parser


def main(argv: list[str] | None = None) -> int:
    """Entry point; returns the exit code."""
    args = build_parser().parse_args(argv)
    try:
        conv = load(Path(args.conventions))
        return args.run(conv, args)
    except ConventionsError as err:
        print(f"conventions unusable: {err}", file=sys.stderr)
        return 2
    except RuntimeError as err:
        print(str(err), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
