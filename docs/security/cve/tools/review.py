#!/usr/bin/env python3
"""Generate the report's shared tables from per-file metadata, and check the rules.

Every finding (findings/*.adoc) and every sweep (sweeps/*.adoc) describes itself
with header attributes. Sub-agents edit only their own file; this script derives
the summary, recommendations, coverage and include lists, so no shared file needs
editing while the review is in progress.

  review.py generate                 write _generated/*.adoc
  review.py check [FILE ...]         structural and evidence checks (draft)
  review.py check --exit FILE ...    exit criteria for one finding or sweep
  review.py check --final            exit criteria for the whole review
  review.py units                    list the units (sweep targets) and their status

Exit status is non-zero when any error is reported.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "_generated"

TRACKS = {"A", "B"}
OUTCOMES = {
    "A": {"not_affected", "affected", "fixed", "under_investigation"},
    "B": {"pattern absent", "weakness possible", "weakness confirmed", "hardening candidate", "undetermined"},
}
JUSTIFICATIONS = {
    "component_not_present", "vulnerable_code_not_present", "vulnerable_code_not_in_execute_path",
    "vulnerable_code_cannot_be_controlled_by_adversary", "inline_mitigations_already_exist",
}
NEEDS_SSVC = {"affected", "under_investigation", "weakness possible", "weakness confirmed"}
SSVC = ["Immediate", "Out-of-Cycle", "Scheduled", "Defer", "n/a"]
ACTIONS = {"fix", "investigate", "add regression test", "add fuzz target", "accept risk", "no action"}
FINDING_STATUS = ["draft", "complete"]
SWEEP_STATUS = {"not-started", "in-progress", "complete", "saturated", "budget-reached"}
SWEEP_DONE = {"complete", "saturated", "budget-reached"}
DISPOSITIONS = {"finding", "duplicate", "triaged-out", "deferred", "pending"}
LABELS = {"Examined-code", "Examined-source", "Tested", "Inferred", "Unverified"}
ESCALATE = {"affected", "weakness confirmed"}
PLACEHOLDER = re.compile(r"_(?:To be|TODO|Pending|not swept|One paragraph|One sentence|List everything|Met, partly)|YYYY|NNNNN|(?<![<\w])<(?!<)[A-Za-z][^<>\n]{2,}>(?!>)")

FINDING_ATTRS = ["finding-id", "finding-title", "finding-track", "finding-sweep", "finding-component",
                 "finding-location", "finding-outcome", "finding-cwe", "finding-ssvc", "finding-about",
                 "finding-ask", "finding-action", "finding-status", "finding-assessed-by"]
SWEEP_ATTRS = ["sweep-id", "sweep-track", "sweep-target", "sweep-status", "sweep-by"]

CELL_SPLIT = re.compile(r"(?<!\\)\|")
LINK = re.compile(r"https://github\.com/roc-lang/roc/blob/([0-9a-f]{7,40})/([^#\[\s]+)#L(\d+)(?:-L(\d+))?\[[^\]]*\]\s*:?\s*(`[^`]+`)?")

errors: list[str] = []
warnings: list[str] = []


def err(where: Path | str, msg: str) -> None:
    errors.append(f"ERROR {rel(where)}: {msg}")


def warn(where: Path | str, msg: str) -> None:
    warnings.append(f"warn  {rel(where)}: {msg}")


def rel(p: Path | str) -> str:
    return str(Path(p).relative_to(ROOT)) if isinstance(p, Path) and p.is_absolute() else str(p)


def attrs(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^:([a-z0-9-]+):\s*(.*)$", line)
        if m and m.group(1) not in out:
            out[m.group(1)] = m.group(2).strip()
    return out


def table_after(text: str, marker: str) -> list[list[str]]:
    """Rows (single-line, header dropped) of the first table after a line equal to marker."""
    lines = text.splitlines()
    try:
        i = next(n for n, l in enumerate(lines) if l.strip() == marker)
    except StopIteration:
        return []
    while i < len(lines) and lines[i].strip() != "|===":
        i += 1
    rows, i = [], i + 1
    while i < len(lines) and lines[i].strip() != "|===":
        line = lines[i].strip()
        if line.startswith("|"):
            rows.append([c.strip() for c in CELL_SPLIT.split(line)[1:]])
        i += 1
    return rows[1:]


def sut_targets() -> dict[str, str]:
    text = (ROOT / "system-under-test.adoc").read_text(encoding="utf-8")
    out = {}
    for marker, track in (("== Component inventory", "A"), ("== Attack-surface map", "B")):
        for row in table_after(text, marker):
            if row and row[0]:
                out[row[0]] = track
    return out


def params() -> dict[str, str]:
    return attrs(ROOT / "index.adoc")


# --------------------------------------------------------------- loading
def load_findings() -> list[tuple[Path, dict[str, str]]]:
    return [(p, attrs(p)) for p in sorted((ROOT / "findings").glob("*.adoc"))]


def load_sweeps() -> list[tuple[Path, dict[str, str], list[list[str]]]]:
    out = []
    for p in sorted((ROOT / "sweeps").glob("*.adoc")):
        out.append((p, attrs(p), table_after(p.read_text(encoding="utf-8"), ".Candidates")))
    return out


def anchor(fid: str) -> str:
    return fid.lower()


def sort_key(a: dict[str, str]):
    ssvc = a.get("finding-ssvc", "n/a")
    return (a.get("finding-track", "B"), SSVC.index(ssvc) if ssvc in SSVC else len(SSVC), a.get("finding-id", ""))


# ------------------------------------------------------------- generate
def generate() -> None:
    GEN.mkdir(exist_ok=True)
    findings = sorted(load_findings(), key=lambda f: sort_key(f[1]))
    sweeps = load_sweeps()
    targets = sut_targets()

    inc = [f"include::../findings/{p.name}[leveloffset=+2]\n" for p, _ in findings]
    (GEN / "findings.adoc").write_text("\n".join(inc) or "No findings.\n", encoding="utf-8")

    rows = ['[cols="3,2,5,5,3,2",options="header"]', "|===",
            "|Finding |Track |What it is about |Where in Roc, and what is asked |Outcome |SSVC"]
    for _, a in findings:
        rows.append(f"|<<{anchor(a.get('finding-id',''))},{a.get('finding-id','')}>> |{a.get('finding-track','')} "
                    f"|{a.get('finding-about','')} |{a.get('finding-location','')}. {a.get('finding-ask','')} "
                    f"|{a.get('finding-outcome','')} {a.get('finding-scope','')} |{a.get('finding-ssvc','')}")
    rows.append("|===")
    (GEN / "summary-table.adoc").write_text("\n".join(rows) + "\n", encoding="utf-8")

    rows = ['[cols="1,3,3,4,2,3",options="header"]', "|===",
            "|# |Finding |Location |Recommended action |SSVC |Owner"]
    n = 0
    for _, a in findings:
        if a.get("finding-action", "no action") == "no action":
            continue
        n += 1
        rows.append(f"|R{n} |<<{anchor(a['finding-id'])},{a['finding-id']}>> |{a.get('finding-location','')} "
                    f"|{a.get('finding-action','')}: {a.get('finding-action-detail','')} |{a.get('finding-ssvc','')} "
                    f"|{a.get('finding-owner','unassigned')}")
    rows.append("|===")
    (GEN / "recommendations-table.adoc").write_text(("\n".join(rows) if n else "No actions were recommended.") + "\n",
                                                    encoding="utf-8")

    by_target = {a.get("sweep-target"): (p, a, c) for p, a, c in sweeps}
    rows = ['[cols="2,7,3,2,3,4",options="header"]', "|===",
            "|Track |Unit (component or class) |Status |Found |Findings |Other"]
    counts = {"sweeps": 0, "sweeps-done": 0, "candidates": 0, "triaged": 0, "deferred": 0, "pending": 0}
    for target, track in sorted(targets.items(), key=lambda t: (t[1], t[0])):
        counts["sweeps"] += 1
        if target not in by_target:
            rows.append(f"|{track} |{target} |not-started | | |")
            continue
        p, a, cands = by_target[target]
        d = [c[1] if len(c) > 1 else "" for c in cands]
        status = a.get("sweep-status", "")
        counts["sweeps-done"] += status in SWEEP_DONE
        counts["candidates"] += len(cands)
        counts["triaged"] += d.count("triaged-out")
        counts["deferred"] += d.count("deferred")
        counts["pending"] += d.count("pending")
        other = ", ".join(f"{d.count(k)} {k}" for k in ("duplicate", "triaged-out", "deferred", "pending") if d.count(k))
        rows.append(f"|{track} |<<{a.get('sweep-id','')},{target}>> |{status} |{len(cands)} |{d.count('finding')} "
                    f"|{other}")
    rows.append("|===")
    (GEN / "coverage-table.adoc").write_text("\n".join(rows) + "\n", encoding="utf-8")
    inc = [f"include::../sweeps/{p.name}[leveloffset=+1]\n" for p, _, _ in sweeps]
    (GEN / "sweeps.adoc").write_text("\n".join(inc) or "No sweeps were run.\n", encoding="utf-8")

    outcomes = [a.get("finding-outcome", "") for _, a in findings]
    stats = {
        "stat-findings": len(findings),
        "stat-findings-complete": sum(a.get("finding-status") == "complete" for _, a in findings),
        "stat-sweeps": counts["sweeps"], "stat-sweeps-done": counts["sweeps-done"],
        "stat-candidates": counts["candidates"], "stat-triaged": counts["triaged"],
        "stat-deferred": counts["deferred"], "stat-pending": counts["pending"],
        "stat-escalations": sum(o in ESCALATE for o in outcomes),
        "stat-recommendations": sum(a.get("finding-action", "no action") != "no action" for _, a in findings),
    }
    (GEN / "stats.adoc").write_text("".join(f":{k}: {v}\n" for k, v in stats.items()), encoding="utf-8")


# ---------------------------------------------------------------- checks
def has_placeholder(line: str) -> bool:
    """Placeholder text outside inline code (`...` or +...+) and outside comments."""
    if line.lstrip().startswith("//"):
        return False
    return bool(PLACEHOLDER.search(re.sub(r"`[^`]*`|\+[^+]*\+", "", line)))


def git_line(sha: str, path: str, start: int, end: int) -> str | None:
    try:
        text = subprocess.run(["git", "-C", os.environ.get("ROC_REPO", str(ROOT)), "show", f"{sha}:{path}"], check=True,
                              capture_output=True, text=True).stdout.splitlines()
    except subprocess.CalledProcessError:
        return None
    if end > len(text):
        return None
    return " ".join(text[start - 1:end])


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.replace("\\|", "|")).strip()


def check_finding(path: Path, a: dict[str, str], commit: str, exit_gate: bool, sweep_ids: set[str]) -> None:
    text = path.read_text(encoding="utf-8")
    for k in FINDING_ATTRS:
        if not a.get(k):
            err(path, f"missing attribute :{k}:")
    fid, track, outcome = a.get("finding-id", ""), a.get("finding-track", ""), a.get("finding-outcome", "")
    if fid and path.stem != fid:
        err(path, f"file name must be {fid}.adoc")
    if f"[[{anchor(fid)}]]" not in text:
        err(path, f"missing anchor [[{anchor(fid)}]]")
    if track not in TRACKS:
        err(path, f"finding-track must be A or B, not {track!r}")
    elif outcome not in OUTCOMES[track]:
        err(path, f"finding-outcome {outcome!r} is not a Track {track} outcome: {sorted(OUTCOMES[track])}")
    if outcome == "not_affected" and a.get("finding-justification") not in JUSTIFICATIONS:
        err(path, "not_affected requires :finding-justification: from the five VEX justifications")
    ssvc = a.get("finding-ssvc", "")
    if ssvc not in SSVC:
        err(path, f"finding-ssvc must be one of {SSVC}")
    elif outcome in NEEDS_SSVC and ssvc == "n/a" and a.get("finding-status") != "draft":
        err(path, f"outcome {outcome!r} requires an SSVC priority")
    if a.get("finding-action") and a["finding-action"] not in ACTIONS:
        err(path, f"finding-action must be one of {sorted(ACTIONS)}")
    status = a.get("finding-status", "")
    if status not in FINDING_STATUS:
        err(path, f"finding-status must be one of {FINDING_STATUS}")
    if a.get("finding-sweep") and a["finding-sweep"] not in sweep_ids:
        err(path, f"finding-sweep {a['finding-sweep']!r} has no sweeps/{a['finding-sweep']}.adoc")
    if track == "B" and "this record does not assert that this project has the same vulnerability" not in text:
        err(path, "Track B findings must carry the analogous-case notice")
    if outcome in ESCALATE:
        warn(path, f"outcome {outcome!r}: apply the handling rule before circulating the report")

    claims = table_after(text, "== Claims")
    if not claims:
        err(path, "no claims table under '== Claims' (one row per line)")
    for row in claims:
        if len(row) < 4:
            err(path, f"claims row has fewer than 4 cells: {row}")
            continue
        cid, label, evidence = row[0], row[2], row[3]
        if label not in LABELS:
            err(path, f"{cid}: label {label!r} is not one of {sorted(LABELS)}")
        links = list(LINK.finditer(evidence))
        if label == "Examined-code" and not links:
            err(path, f"{cid}: Examined-code needs a pinned GitHub link with a quoted line")
        for m in links:
            sha, file, start, end, quote = m.group(1), m.group(2), int(m.group(3)), int(m.group(4) or m.group(3)), m.group(5)
            if commit and not commit.startswith(sha) and sha != commit:
                err(path, f"{cid}: link pinned to {sha}, not the assessed commit")
            if not quote:
                err(path, f"{cid}: link to {file}#L{start} has no quoted line after it")
                continue
            actual = git_line(sha, file, start, end)
            if actual is None:
                err(path, f"{cid}: {file}#L{start} does not exist at {sha[:10]}")
            elif norm(quote.strip("`")) not in norm(actual):
                err(path, f"{cid}: quote does not match {file}:{start} at {sha[:10]}: {norm(actual)!r}")
        if label == "Unverified" and "check" not in evidence.lower() and "<<" not in evidence:
            err(path, f"{cid}: an Unverified claim must name the check that would settle it")

    if exit_gate:
        if status == "draft":
            err(path, "exit: status is still draft")
        for n, line in enumerate(text.splitlines(), 1):
            if has_placeholder(line):
                err(path, f"exit: placeholder on line {n}: {line.strip()[:80]}")


def check_sweep(path: Path, a: dict[str, str], cands: list[list[str]], targets: dict[str, str],
                finding_ids: set[str], exit_gate: bool, budget: int) -> None:
    for k in SWEEP_ATTRS:
        if not a.get(k):
            err(path, f"missing attribute :{k}:")
    if a.get("sweep-id") and path.stem != a["sweep-id"]:
        err(path, f"file name must be {a['sweep-id']}.adoc")
    if a.get("sweep-id") and f"[[{a['sweep-id']}]]" not in path.read_text(encoding="utf-8"):
        err(path, f"missing anchor [[{a['sweep-id']}]]")
    target = a.get("sweep-target", "")
    if target and target not in targets:
        err(path, f"sweep-target {target!r} is not a row in the system-under-test inventory or attack-surface map")
    elif target and a.get("sweep-track") != targets[target]:
        err(path, f"sweep-track must be {targets[target]} for {target!r}")
    status = a.get("sweep-status", "")
    if status not in SWEEP_STATUS:
        err(path, f"sweep-status must be one of {sorted(SWEEP_STATUS)}")
    if status == "budget-reached" and a.get("sweep-track") != "B":
        err(path, "budget-reached applies only to Track B; Track A sweeps must be complete")
    text = path.read_text(encoding="utf-8")
    if not table_after(text, ".Queries"):
        err(path, "no rows in the '.Queries' table")
    n_findings = 0
    for row in cands:
        if len(row) < 3:
            err(path, f"candidate row needs at least: id | disposition | reason: {row}")
            continue
        cid, disp, reason = row[0], row[1], row[2]
        if disp not in DISPOSITIONS:
            err(path, f"{cid}: disposition {disp!r} is not one of {sorted(DISPOSITIONS)}")
        if disp == "finding":
            n_findings += 1
            if cid not in finding_ids:
                err(path, f"{cid}: disposition is 'finding' but findings/{cid}.adoc does not exist")
        if disp == "duplicate" and cid not in finding_ids:
            err(path, f"{cid}: disposition is 'duplicate' but no findings/{cid}.adoc exists (it must be assessed by another unit)")
        if disp in ("triaged-out", "deferred") and len(reason) < 20:
            err(path, f"{cid}: {disp} needs a reason with evidence")
    if a.get("sweep-track") == "B" and n_findings > budget:
        err(path, f"{n_findings} findings exceed the Track B budget of {budget} per class")
    if exit_gate:
        if status not in SWEEP_DONE:
            err(path, f"exit: sweep-status is {status!r}")
        if any(len(r) > 1 and r[1] == "pending" for r in cands):
            err(path, "exit: candidates are still pending")
        for n, line in enumerate(text.splitlines(), 1):
            if has_placeholder(line):
                err(path, f"exit: placeholder on line {n}: {line.strip()[:80]}")
        if status == "saturated" and not a.get("sweep-stop-reason"):
            err(path, "exit: saturated requires :sweep-stop-reason:")


def check(files: list[str], exit_gate: bool, final: bool) -> None:
    p = params()
    commit = p.get("roc-commit", "")
    budget = int(p.get("track-b-budget", "3"))
    targets = sut_targets()
    findings = load_findings()
    sweeps = load_sweeps()
    finding_ids = {a.get("finding-id", "") for _, a in findings}
    sweep_ids = {a.get("sweep-id", "") for _, a, _ in sweeps}
    wanted = {(ROOT / f).resolve() for f in files}

    for path, a in findings:
        if not wanted or path in wanted:
            check_finding(path, a, commit, exit_gate or final, sweep_ids)
    for path, a, cands in sweeps:
        if not wanted or path in wanted:
            check_sweep(path, a, cands, targets, finding_ids, exit_gate or final, budget)

    referenced = {r[0] for _, _, c in sweeps for r in c if len(r) > 1 and r[1] == "finding"}
    for path, a in findings:
        if (not wanted or path in wanted) and a.get("finding-id") not in referenced:
            err(path, "no sweep lists this finding as a candidate with disposition 'finding'")

    if final:
        covered = {a.get("sweep-target") for _, a, _ in sweeps}
        for target in targets:
            if target not in covered:
                err("coverage", f"no sweep for {target!r}")
        max_findings = int(p.get("max-findings", "0") or 0)
        if max_findings and len(findings) > max_findings:
            err("findings", f"{len(findings)} findings exceed max-findings {max_findings}")
        for f in ["index.adoc", "summary.adoc", "conclusions.adoc", "system-under-test.adoc", "approach.adoc"]:
            for n, line in enumerate((ROOT / f).read_text(encoding="utf-8").splitlines(), 1):
                if has_placeholder(line):
                    err(f, f"placeholder on line {n}: {line.strip()[:80]}")
        if "skeleton" in (ROOT / "system-under-test.adoc").read_text(encoding="utf-8").lower():
            err("system-under-test.adoc", "the skeleton evidence callout is still present")
        for path, a in findings:
            if a.get("finding-status") != "complete":
                err(path, "final: finding is not complete")


def main(argv: list[str]) -> int:
    if argv and argv[0] == "units":
        sweeps = {a.get("sweep-target"): (p, a) for p, a, _ in load_sweeps()}
        for target, track in sorted(sut_targets().items(), key=lambda t: (t[1], t[0])):
            p, a = sweeps.get(target, (None, {}))
            print(f"{track}  {a.get('sweep-status', 'not-started'):14}  {p.name if p else '-':32}  {target}")
        return 0
    if not argv or argv[0] not in ("generate", "check"):
        print(__doc__)
        return 2
    if argv[0] == "generate":
        generate()
        return 0
    rest = argv[1:]
    exit_gate, final = "--exit" in rest, "--final" in rest
    check([f for f in rest if not f.startswith("--")], exit_gate, final)
    for line in warnings + errors:
        print(line)
    print(f"{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
