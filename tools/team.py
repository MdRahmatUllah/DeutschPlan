"""The team board: how parallel agents claim work, record it and report back.

`ONBOARDING.md` (§3, the team) is the protocol; this is the only thing
that edits the board. The board is the `team` branch, kept off `main` because
CI runs on every push to `main` and the board changes all day:

    TASKS.md        the task file: every issue, who has it, the shared locks,
                    and the handoffs — assignments, review requests, reports
    STATUS.md       generated from TASKS.md on every change: the project status
    MEMORY.md       the project's memory: what every agent should know
    WORKLOG.md      the running record of what each agent is doing
    PLAN.md         the plan for every milestone: lanes, order, decisions
    agents/<id>.md  one agent's memory: now, next, and notes for its next session

Every change is a transaction against `origin/team`: fetch, reset to it,
apply the change, commit, push. A rejected push means another agent got there
first, so the change is re-applied to their version and re-checked against
it. The push is the compare-and-swap: two agents can never both claim an
issue, and nobody resolves a merge conflict on the board.

    python tools/team.py agents            # who is active, who is free
    python tools/team.py join agent-2      # take an identity, once per session
    python tools/team.py status            # handoffs for me, my work, what is ready
    python tools/team.py claim 137
    python tools/team.py log -m "results list and the FTS query done"
    python tools/team.py review 137 --pr 281
    python tools/team.py done 137 -m "SearchRoute takes ?step= now"
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

BRANCH = "team"

# The project's commit identity: every change reaching GitHub is made as the
# repository owner (the owner's rule; see CLAUDE.md).
AUTHOR_NAME = "MdRahmatUllah"
AUTHOR_EMAIL = "rahmat.ullah@infinitibit.com"

STATUSES = ("open", "assigned", "in-progress", "review", "done", "needs-decision")
AGENT_ID = re.compile(r"^agent-[1-9]$")
STAMP = "%Y-%m-%d %H:%M"

# An identity nobody has used for this long is free to take over: its last
# session ended without `leave`.
IDLE_AFTER = timedelta(hours=2)

# A device lock older than this is abandoned: a device check takes minutes,
# and an agent that died holding it must not block the emulator all day.
DEVICE_LOCK_STALE_SECONDS = 45 * 60


class Refused(Exception):
    """The board says no: already claimed, blocked, not yours."""


def now() -> str:
    return datetime.now().strftime(STAMP)


# --- TASKS.md --------------------------------------------------------------------

@dataclass
class Task:
    issue: int
    ms: str
    lane: str
    pri: str
    size: str
    title: str
    status: str = "open"
    owner: str = ""
    blocked_by: list[int] = field(default_factory=list)
    pr: str = ""

    def row(self) -> str:
        cells = (
            f"#{self.issue}", self.ms, self.lane, self.pri, self.size,
            self.title.replace("|", "/"), self.status, self.owner,
            " ".join(f"#{n}" for n in self.blocked_by), self.pr,
        )
        return "| " + " | ".join(cells) + " |"


@dataclass
class Lock:
    resource: str
    owner: str = ""
    since: str = ""
    why: str = ""

    def row(self) -> str:
        return "| " + " | ".join((self.resource, self.owner, self.since, self.why.replace("|", "/"))) + " |"


def _cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _table(lines: list[str], heading: str) -> tuple[int, int]:
    """The line span of the rows of the table under `## heading`."""
    try:
        start = lines.index(f"## {heading}")
    except ValueError as missing:
        raise SystemExit(f"TASKS.md has no '## {heading}' section") from missing
    header = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("|"))
    first = end = header + 2  # past the header and its |---| rule
    while end < len(lines) and lines[end].startswith("|"):
        end += 1
    return first, end


class Board:
    """TASKS.md: the task and lock tables, and the handoffs appended below."""

    def __init__(self, text: str):
        self.text = text
        lines = text.splitlines()
        first, end = _table(lines, "Tasks")
        self.tasks = []
        for c in (_cells(line) for line in lines[first:end]):
            self.tasks.append(Task(
                issue=int(c[0].lstrip("#")), ms=c[1], lane=c[2], pri=c[3], size=c[4],
                title=c[5], status=c[6], owner=c[7],
                blocked_by=[int(n.lstrip("#")) for n in c[8].split()], pr=c[9],
            ))
        first, end = _table(lines, "Locks")
        self.locks = [Lock(*_cells(line)[:4]) for line in lines[first:end]]
        self.new_handoffs: list[str] = []

    def task(self, issue: int) -> Task:
        for task in self.tasks:
            if task.issue == issue:
                return task
        raise Refused(f"#{issue} is not on the board (add it with: team.py add {issue} --lane X)")

    def status_of(self, issue: int) -> str:
        """A blocker not on the board was closed before the board was made."""
        return next((t.status for t in self.tasks if t.issue == issue), "done")

    def ready(self, task: Task) -> bool:
        return all(self.status_of(n) == "done" for n in task.blocked_by)

    def handoff_ids(self) -> list[int]:
        text = self.text + "".join(self.new_handoffs)
        return [int(n) for n in re.findall(r"^### H-(\d+) ", text, re.M)]

    def handoff(self, sender: str, to: str, kind: str, body: str, issue: int | None = None) -> int:
        number = max(self.handoff_ids(), default=0) + 1
        tag = f" · #{issue}" if issue else ""
        self.new_handoffs.append(f"\n### H-{number} · {now()} · {sender} → {to} · {kind}{tag}\n\n{body.strip()}\n")
        return number

    def render(self) -> str:
        lines = self.text.splitlines()
        for heading, rows in (("Tasks", [t.row() for t in self.tasks]), ("Locks", [lk.row() for lk in self.locks])):
            first, end = _table(lines, heading)
            lines[first:end] = rows
        return "\n".join(lines) + "\n" + "".join(self.new_handoffs)


def handoffs_for(text: str, agent: str, after: int) -> list[str]:
    """Handoffs to [agent] or to everyone, newer than [after], not its own."""
    shown = []
    for entry in re.split(r"(?m)^(?=### H-\d+ )", text):
        m = re.match(r"### H-(\d+) · [^·]+ · (\S+) → (\S+) ·", entry)
        if m and int(m.group(1)) > after and m.group(3) in (agent, "all") and m.group(2) != agent:
            shown.append(entry.strip())
    return shown


def task_from_issue(issue: int, data: dict, lane: str) -> Task:
    labels = [label["name"] for label in data.get("labels", [])]
    pri = next((label for label in labels if re.fullmatch(r"P\d", label)), "-")
    size = next((label.split(":")[1] for label in labels if label.startswith("size:")), "-")
    ms = ((data.get("milestone") or {}).get("title") or "-").split(" ")[0]
    deps = re.search(r"## Dependencies\s*\n(.*?)(?:\n## |\n---|\Z)", data.get("body") or "", re.S)
    blocked = sorted({int(n) for n in re.findall(r"#(\d+)", deps.group(1))}) if deps else []
    return Task(issue, ms, lane, pri, size, data["title"], blocked_by=blocked)


# --- agents/<id>.md: one agent's memory --------------------------------------------

AGENT_TEMPLATE = """# {agent}

session: active
last-seen: {stamp}
last-read: 0

## Now

Nothing claimed.

## Next

Run `python tools/team.py status` and claim a ready task.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

"""


def agent_path(root: Path, agent: str) -> Path:
    return root / "agents" / f"{agent}.md"


def read_field(text: str, name: str) -> str:
    m = re.search(rf"^{name}: (.*)$", text, re.M)
    return m.group(1).strip() if m else ""


def write_field(root: Path, agent: str, name: str, value: str) -> None:
    path = agent_path(root, agent)
    text = path.read_text(encoding="utf-8")
    text, count = re.subn(rf"^{name}: .*$", f"{name}: {value}", text, count=1, flags=re.M)
    if not count:
        raise SystemExit(f"{path.name} has no '{name}:' line")
    path.write_text(text, encoding="utf-8", newline="\n")


def set_section(root: Path, agent: str, heading: str, body: str, append: bool = False) -> None:
    path = agent_path(root, agent)
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(rf"(^## {re.escape(heading)}\n\n)(.*?)(?=^## |\Z)", re.M | re.S)
    m = pattern.search(text)
    if not m:
        raise SystemExit(f"{path.name} has no '## {heading}' section")
    new = (m.group(2).rstrip() + "\n" if append else "") + body.strip() + "\n\n"
    path.write_text(text[: m.start(2)] + new + text[m.end(2):], encoding="utf-8", newline="\n")


def identities(root: Path) -> list[tuple[str, str, str, str]]:
    """(agent, session, last-seen, now) for every agent file."""
    rows = []
    for path in sorted((root / "agents").glob("agent-*.md")):
        text = path.read_text(encoding="utf-8")
        now_line = re.search(r"^## Now\n\n(.*)$", text, re.M)
        rows.append((path.stem, read_field(text, "session"), read_field(text, "last-seen"), now_line.group(1) if now_line else ""))
    return rows


def is_idle(session: str, last_seen: str) -> bool:
    if session != "active":
        return True
    try:
        return datetime.now() - datetime.strptime(last_seen, STAMP) > IDLE_AFTER
    except ValueError:
        return True


# --- WORKLOG.md, MEMORY.md, STATUS.md --------------------------------------------------

def append_log(root: Path, agent: str, text: str, issue: int | None = None) -> None:
    tag = f" #{issue}" if issue else ""
    with (root / "WORKLOG.md").open("a", encoding="utf-8", newline="\n") as log:
        log.write(f"- {now()} · {agent}{tag} · {text}\n")


def remember(root: Path, agent: str, topic: str, text: str) -> None:
    with (root / "MEMORY.md").open("a", encoding="utf-8", newline="\n") as memory:
        memory.write(f"- **{topic}** ({now()[:10]}, {agent}): {text.strip()}\n")


def render_status(root: Path) -> None:
    board = Board((root / "TASKS.md").read_text(encoding="utf-8"))
    order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
    out = [
        "# Project status",
        "",
        f"Generated by `tools/team.py` from TASKS.md at {now()}. Do not edit: it is rewritten on every board change.",
        "",
        "## Milestones",
        "",
        "| Milestone | Done | In flight | Open | Needs a decision |",
        "|---|---|---|---|---|",
    ]
    for ms in sorted({t.ms for t in board.tasks}):
        tasks = [t for t in board.tasks if t.ms == ms]
        count = lambda *s: sum(1 for t in tasks if t.status in s)  # noqa: E731
        out.append(f"| {ms} | {count('done')} of {len(tasks)} | {count('in-progress', 'review')} | {count('open', 'assigned')} | {count('needs-decision')} |")
    out += ["", "## Agents", "", "| Agent | Session | Last seen | Now |", "|---|---|---|---|"]
    for agent, session, seen, doing in identities(root):
        out.append(f"| {agent} | {'idle' if is_idle(session, seen) else 'active'} | {seen} | {doing} |")
    out += ["", "## In flight", ""]
    flight = [t for t in board.tasks if t.status in ("in-progress", "review", "assigned")]
    out += [f"- #{t.issue} {t.status} · {t.owner} {t.pr} · {t.title}" for t in flight] or ["- nothing"]
    out += ["", "## Ready to claim", ""]
    ready = sorted((t for t in board.tasks if t.status == "open" and board.ready(t)), key=lambda t: (t.ms, order.get(t.pri, 9), t.issue))
    out += [f"- #{t.issue} {t.ms} · lane {t.lane} · {t.pri} · {t.title}" for t in ready] or ["- nothing"]
    out += ["", "## Waiting on a decision from the owner", ""]
    out += [f"- #{t.issue} {t.title}" for t in board.tasks if t.status == "needs-decision"] or ["- nothing"]
    held = [lk for lk in board.locks if lk.owner]
    out += ["", "## Locks held", ""]
    out += [f"- {lk.resource}: {lk.owner} since {lk.since} — {lk.why}" for lk in held] or ["- none"]
    (root / "STATUS.md").write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")


# --- Git: the transaction ---------------------------------------------------------------

def git(root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(root), "-c", f"user.name={AUTHOR_NAME}", "-c", f"user.email={AUTHOR_EMAIL}", *args],
        capture_output=True, text=True, encoding="utf-8", check=check,
    )


def sync(root: Path) -> None:
    git(root, "fetch", "--quiet", "origin", BRANCH)
    git(root, "reset", "--quiet", "--hard", f"origin/{BRANCH}")


def transact(root: Path, agent: str, message: str, change, attempts: int = 8):
    """Apply [change] on top of origin/team and push it.

    [change] reads and writes files under [root] and returns a result. After a
    rejected push it runs again from a fresh copy, so it must decide from what
    it reads now, never from what it read on an earlier attempt.
    """
    for attempt in range(attempts):
        sync(root)
        result = change(root)
        if agent_path(root, agent).exists():
            write_field(root, agent, "last-seen", now())
        render_status(root)
        git(root, "add", "-A")
        git(root, "commit", "--quiet", "-m", f"{agent}: {message}")
        if git(root, "push", "--quiet", "origin", f"HEAD:{BRANCH}", check=False).returncode == 0:
            return result
        time.sleep(0.3 + random.random() * (attempt + 1))
    raise SystemExit("the board is busy: gave up after several rejected pushes — try again")


def on_board(change):
    """A board edit as a transaction step: parse TASKS.md, change it, write it."""
    def step(root: Path):
        path = root / "TASKS.md"
        board = Board(path.read_text(encoding="utf-8"))
        result = change(root, board)
        path.write_text(board.render(), encoding="utf-8", newline="\n")
        return result
    return step


# --- Commands ------------------------------------------------------------------------------

def cmd_claim(root: Path, agent: str, issue: int) -> None:
    def change(root, board):
        task = board.task(issue)
        busy = [t for t in board.tasks if t.owner == agent and t.status == "in-progress" and t.issue != issue]
        if busy:
            raise Refused(f"you already have #{busy[0].issue} in progress: `review`, `done` or `release` it first")
        if task.status == "assigned" and task.owner != agent:
            raise Refused(f"#{issue} is assigned to {task.owner}")
        if task.status not in ("open", "assigned"):
            raise Refused(f"#{issue} is {task.status}" + (f" ({task.owner})" if task.owner else ""))
        if not board.ready(task):
            waiting = " ".join(f"#{n}" for n in task.blocked_by if board.status_of(n) != "done")
            raise Refused(f"#{issue} is blocked by {waiting}")
        task.status, task.owner = "in-progress", agent
        set_section(root, agent, "Now", f"#{issue} {task.title} — claimed {now()}.")
        append_log(root, agent, f"claimed: {task.title}", issue)
    transact(root, agent, f"claim #{issue}", on_board(change))
    print(f"claimed #{issue}")


def cmd_assign(root: Path, agent: str, issue: int, to: str, message: str) -> None:
    check_agent(to)
    def change(root, board):
        task = board.task(issue)
        if task.status not in ("open", "assigned"):
            raise Refused(f"#{issue} is {task.status}; only open work can be assigned")
        task.status, task.owner = "assigned", to
        board.handoff(agent, to, "assign", message or f"Please take #{issue} ({task.title}).", issue)
        append_log(root, agent, f"assigned to {to}", issue)
    transact(root, agent, f"assign #{issue} to {to}", on_board(change))
    print(f"assigned #{issue} to {to}")


def cmd_release(root: Path, agent: str, issue: int, message: str) -> None:
    def change(root, board):
        task = board.task(issue)
        if task.owner != agent:
            raise Refused(f"#{issue} is not yours ({task.owner or 'nobody'})")
        task.status, task.owner = "open", ""
        board.handoff(agent, "all", "note", f"Released #{issue}: {message}", issue)
        set_section(root, agent, "Now", "Nothing claimed.")
        append_log(root, agent, f"released: {message}", issue)
    transact(root, agent, f"release #{issue}", on_board(change))
    print(f"released #{issue}")


def cmd_review(root: Path, agent: str, issue: int, pr: int, to: str) -> None:
    def change(root, board):
        task = board.task(issue)
        if task.owner != agent:
            raise Refused(f"#{issue} is not yours ({task.owner or 'nobody'})")
        task.status, task.pr = "review", f"#{pr}"
        board.handoff(agent, to, "review-request",
                      f"PR #{pr} for #{issue} ({task.title}) is up. Review it on GitHub and answer with `team.py msg {agent} --kind review`.", issue)
        set_section(root, agent, "Now", f"#{issue} in review as PR #{pr}: watch CI, answer review threads, merge.")
        append_log(root, agent, f"PR #{pr} open; review requested from {to}", issue)
    transact(root, agent, f"review #{issue} (PR #{pr})", on_board(change))
    print(f"#{issue} in review as PR #{pr}")


def issue_closed(issue: int) -> bool:
    out = subprocess.run(["gh", "issue", "view", str(issue), "--json", "state", "--jq", ".state"],
                         capture_output=True, text=True, check=False)
    return out.stdout.strip() == "CLOSED"


def cmd_done(root: Path, agent: str, issue: int, pr: int | None, message: str, check_closed=issue_closed) -> None:
    if check_closed is not None and not check_closed(issue):
        raise Refused(f"#{issue} is still open on GitHub: merge its PR (with 'Closes #{issue}') first")
    def change(root, board):
        task = board.task(issue)
        if task.owner != agent:
            raise Refused(f"#{issue} is not yours ({task.owner or 'nobody'})")
        task.status = "done"
        if pr:
            task.pr = f"#{pr}"
        freed = [t for t in board.tasks if t.status == "open" and issue in t.blocked_by and board.ready(t)]
        report = f"#{issue} ({task.title}) is merged" + (f" as {task.pr}" if task.pr else "") + "."
        if message:
            report += f" {message}"
        if freed:
            report += " Now ready: " + ", ".join(f"#{t.issue}" for t in freed) + "."
        board.handoff(agent, "all", "report", report, issue)
        set_section(root, agent, "Now", "Nothing claimed.")
        append_log(root, agent, "done" + (f" ({task.pr})" if task.pr else ""), issue)
    transact(root, agent, f"done #{issue}", on_board(change))
    print(f"#{issue} done")


def cmd_decision(root: Path, agent: str, issue: int, message: str) -> None:
    def change(root, board):
        task = board.task(issue)
        task.status, task.owner = "needs-decision", ""
        board.handoff(agent, "owner", "decision", message, issue)
        append_log(root, agent, f"needs the owner's decision: {message}", issue)
    transact(root, agent, f"decision needed on #{issue}", on_board(change))
    print(f"#{issue} waits for the owner's decision")


def cmd_reopen(root: Path, agent: str, issue: int, message: str) -> None:
    """A decision was made, or a claim went stale: the issue is open again."""
    def change(root, board):
        task = board.task(issue)
        task.status, task.owner = "open", ""
        board.handoff(agent, "all", "note", f"#{issue} is open again: {message}", issue)
        append_log(root, agent, f"reopened: {message}", issue)
    transact(root, agent, f"reopen #{issue}", on_board(change))
    print(f"#{issue} open")


def cmd_lock(root: Path, agent: str, resource: str, message: str, release: bool) -> None:
    def change(root, board):
        lock = next((lk for lk in board.locks if lk.resource == resource), None)
        if lock is None:
            raise Refused(f"no lock called {resource!r}; the locks are: {', '.join(lk.resource for lk in board.locks)}")
        if release:
            if lock.owner != agent:
                raise Refused(f"{resource} is held by {lock.owner or 'nobody'}")
            lock.owner = lock.since = lock.why = ""
        else:
            if lock.owner and lock.owner != agent:
                raise Refused(f"{resource} is held by {lock.owner} since {lock.since}: {lock.why}")
            lock.owner, lock.since, lock.why = agent, now(), message
        append_log(root, agent, f"{'unlocked' if release else 'locked'} {resource}" + (f": {message}" if message else ""))
    transact(root, agent, f"{'unlock' if release else 'lock'} {resource}", on_board(change))
    print(f"{resource} {'released' if release else 'held'}")


def cmd_msg(root: Path, agent: str, to: str, kind: str, message: str, issue: int | None) -> None:
    if to not in ("all", "owner"):
        check_agent(to)
    number = transact(root, agent, f"{kind} to {to}", on_board(lambda root, board: board.handoff(agent, to, kind, message, issue)))
    print(f"H-{number} sent to {to}")


def cmd_ack(root: Path, agent: str) -> None:
    def change(root):
        latest = max(Board((root / "TASKS.md").read_text(encoding="utf-8")).handoff_ids(), default=0)
        write_field(root, agent, "last-read", str(latest))
        return latest
    print(f"read up to H-{transact(root, agent, 'ack', change)}")


def cmd_add(root: Path, agent: str, issue: int, lane: str) -> None:
    """Put a new GitHub issue — a follow-up, a bug — on the board."""
    raw = subprocess.run(["gh", "issue", "view", str(issue), "--json", "title,milestone,labels,body"],
                         capture_output=True, text=True, check=True).stdout
    task = task_from_issue(issue, json.loads(raw), lane)
    def change(root, board):
        if any(t.issue == issue for t in board.tasks):
            raise Refused(f"#{issue} is already on the board")
        board.tasks.append(task)
        board.handoff(agent, "all", "note", f"Added #{issue} ({task.title}) to lane {lane}.", issue)
        append_log(root, agent, f"added to the board, lane {lane}", issue)
    transact(root, agent, f"add #{issue}", on_board(change))
    print(f"#{issue} added")


def cmd_join(root: Path, agent: str, force: bool) -> None:
    def change(root):
        path = agent_path(root, agent)
        if not path.exists():
            path.parent.mkdir(exist_ok=True)
            path.write_text(AGENT_TEMPLATE.format(agent=agent, stamp=now()), encoding="utf-8", newline="\n")
            append_log(root, agent, "joined the team")
            return
        text = path.read_text(encoding="utf-8")
        if not force and not is_idle(read_field(text, "session"), read_field(text, "last-seen")):
            raise Refused(f"{agent} looks active (last seen {read_field(text, 'last-seen')}): take an idle identity, or --force if that session is gone")
        write_field(root, agent, "session", "active")
        append_log(root, agent, "session started")
    transact(root, agent, "join", change)


def cmd_leave(root: Path, agent: str, message: str) -> None:
    def change(root):
        write_field(root, agent, "session", "idle")
        if message:
            set_section(root, agent, "Memory", f"- {now()} (end of session): {message}", append=True)
        append_log(root, agent, "session ended" + (f": {message}" if message else ""))
    transact(root, agent, "leave", change)
    print(f"{agent} is idle; its memory is in agents/{agent}.md")


def cmd_status(root: Path, agent: str) -> None:
    sync(root)
    text = (root / "TASKS.md").read_text(encoding="utf-8")
    board = Board(text)
    after = int(read_field(agent_path(root, agent).read_text(encoding="utf-8"), "last-read") or 0)
    unread = handoffs_for(text, agent, after)
    print(f"== {agent}: {len(unread)} unread handoff(s)" + (" — act on them, then `team.py ack`" if unread else ""))
    for entry in unread:
        print("   " + entry.replace("\n", "\n   "))
    print("== mine")
    for t in board.tasks:
        if t.owner == agent and t.status != "done":
            print(f"   #{t.issue} {t.status} {t.pr} — {t.title}")
    print("== others in flight")
    for t in board.tasks:
        if t.status in ("in-progress", "review", "assigned") and t.owner != agent:
            print(f"   #{t.issue} {t.status} {t.owner} {t.pr} — {t.title}")
    order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
    ready = sorted((t for t in board.tasks if board.ready(t) and (t.status == "open" or (t.status == "assigned" and t.owner == agent))),
                   key=lambda t: (t.owner != agent, t.ms, order.get(t.pri, 9), t.issue))
    print("== ready to claim (yours first, then milestone and priority)")
    for t in ready:
        print(f"   #{t.issue} {t.ms} lane {t.lane} {t.pri} {t.size} — {t.title}" + (" [assigned to you]" if t.owner == agent else ""))
    held = [lk for lk in board.locks if lk.owner]
    print("== locks held: " + (", ".join(f"{lk.resource} by {lk.owner} ({lk.why})" for lk in held) or "none"))


def cmd_agents(root: Path) -> None:
    sync(root)
    for agent, session, seen, doing in identities(root):
        print(f"{agent}  {'idle' if is_idle(session, seen) else 'ACTIVE'}  last seen {seen}  now: {doing}")


def cmd_device(team_root: Path, agent: str, release: bool) -> None:
    """The emulator is one device on one machine: a local lock, not a board one."""
    lock = team_root / ".device.lock"
    owner_file = lock / "owner"
    if release:
        if owner_file.exists() and owner_file.read_text(encoding="utf-8").split()[0] != agent:
            raise Refused(f"the device is held by {owner_file.read_text(encoding='utf-8').strip()}, not you")
        if owner_file.exists():
            owner_file.unlink()
        if lock.exists():
            lock.rmdir()
        print("device released")
        return
    try:
        lock.mkdir()  # atomic: exactly one agent gets it
    except FileExistsError:
        age = time.time() - lock.stat().st_mtime
        holder = owner_file.read_text(encoding="utf-8").strip() if owner_file.exists() else "?"
        if age < DEVICE_LOCK_STALE_SECONDS:
            raise Refused(f"the device is in use by {holder} ({int(age // 60)} min): do other work and try again") from None
        print(f"breaking a stale device lock ({holder}, {int(age // 60)} min)")
        if owner_file.exists():
            owner_file.unlink()
        lock.rmdir()
        lock.mkdir()
    owner_file.write_text(f"{agent} {now()}\n", encoding="utf-8")
    print("device held: `team.py device --release` the moment the check is over")


# --- Where things are ------------------------------------------------------------------------

def check_agent(agent: str) -> str:
    if not AGENT_ID.match(agent):
        raise SystemExit(f"agent ids are agent-1 … agent-9, not {agent!r}")
    return agent


def _git_out(*args: str) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout.strip()


def team_root() -> Path:
    """`<parent of the main checkout>/dp-team`: the same from every worktree."""
    if os.environ.get("DP_TEAM_ROOT"):
        return Path(os.environ["DP_TEAM_ROOT"])
    return Path(_git_out("rev-parse", "--path-format=absolute", "--git-common-dir")).parent.parent / "dp-team"


def my_agent() -> str:
    marker = Path(_git_out("rev-parse", "--show-toplevel")) / ".dp-agent"
    if not marker.exists():
        raise SystemExit("this worktree has no agent: run `python tools/team.py agents`, then `join agent-N`")
    return check_agent(marker.read_text(encoding="utf-8").strip())


def board_checkout(agent: str) -> Path:
    """This agent's own clone of the team branch, made on first use."""
    root = team_root() / agent
    if not root.exists():
        root.parent.mkdir(parents=True, exist_ok=True)
        url = _git_out("remote", "get-url", "origin")
        subprocess.run(["git", "clone", "--quiet", "--single-branch", "--branch", BRANCH, url, str(root)], check=True)
    return root


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="team.py", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("agents")
    p = sub.add_parser("join"); p.add_argument("agent"); p.add_argument("--force", action="store_true")
    p = sub.add_parser("leave"); p.add_argument("-m", default="")
    sub.add_parser("status")
    p = sub.add_parser("claim"); p.add_argument("issue", type=int)
    p = sub.add_parser("assign"); p.add_argument("issue", type=int); p.add_argument("to"); p.add_argument("-m", default="")
    p = sub.add_parser("release"); p.add_argument("issue", type=int); p.add_argument("-m", required=True)
    p = sub.add_parser("review"); p.add_argument("issue", type=int); p.add_argument("--pr", type=int, required=True); p.add_argument("--to", default="all")
    p = sub.add_parser("done"); p.add_argument("issue", type=int); p.add_argument("--pr", type=int); p.add_argument("-m", default="")
    p = sub.add_parser("decision"); p.add_argument("issue", type=int); p.add_argument("-m", required=True)
    p = sub.add_parser("reopen"); p.add_argument("issue", type=int); p.add_argument("-m", required=True)
    p = sub.add_parser("log"); p.add_argument("-m", required=True); p.add_argument("--issue", type=int)
    p = sub.add_parser("next"); p.add_argument("-m", required=True)
    p = sub.add_parser("note"); p.add_argument("-m", required=True)
    p = sub.add_parser("remember"); p.add_argument("topic"); p.add_argument("-m", required=True)
    p = sub.add_parser("msg"); p.add_argument("to"); p.add_argument("-m", required=True); p.add_argument("--issue", type=int)
    p.add_argument("--kind", default="note", choices=("note", "question", "answer", "report", "heads-up", "review"))
    sub.add_parser("ack")
    p = sub.add_parser("lock"); p.add_argument("resource"); p.add_argument("-m", required=True)
    p = sub.add_parser("unlock"); p.add_argument("resource")
    p = sub.add_parser("add"); p.add_argument("issue", type=int); p.add_argument("--lane", required=True)
    p = sub.add_parser("device"); p.add_argument("--release", action="store_true")
    args = parser.parse_args(argv)

    try:
        if args.cmd == "agents":
            cmd_agents(board_checkout("view"))  # a read-only clone: nobody's identity yet
            return 0
        if args.cmd == "join":
            agent = check_agent(args.agent)
            cmd_join(board_checkout(agent), agent, args.force)
            (Path(_git_out("rev-parse", "--show-toplevel")) / ".dp-agent").write_text(agent + "\n", encoding="utf-8")
            print(f"you are {agent}: read {team_root() / agent / 'agents' / (agent + '.md')} — your memory — then `team.py status`")
            return 0
        agent = my_agent()
        root = board_checkout(agent)
        match args.cmd:
            case "leave": cmd_leave(root, agent, args.m)
            case "status": cmd_status(root, agent)
            case "claim": cmd_claim(root, agent, args.issue)
            case "assign": cmd_assign(root, agent, args.issue, args.to, args.m)
            case "release": cmd_release(root, agent, args.issue, args.m)
            case "review": cmd_review(root, agent, args.issue, args.pr, args.to)
            case "done": cmd_done(root, agent, args.issue, args.pr, args.m)
            case "decision": cmd_decision(root, agent, args.issue, args.m)
            case "reopen": cmd_reopen(root, agent, args.issue, args.m)
            case "log": transact(root, agent, "log", lambda r: append_log(r, agent, args.m, args.issue)); print("logged")
            case "next": transact(root, agent, "next", lambda r: set_section(r, agent, "Next", args.m)); print("next updated")
            case "note": transact(root, agent, "note", lambda r: set_section(r, agent, "Memory", f"- {now()}: {args.m}", append=True)); print("noted in your memory")
            case "remember": transact(root, agent, f"remember {args.topic}", lambda r: remember(r, agent, args.topic, args.m)); print("added to MEMORY.md")
            case "msg": cmd_msg(root, agent, args.to, args.kind, args.m, args.issue)
            case "ack": cmd_ack(root, agent)
            case "lock": cmd_lock(root, agent, args.resource, args.m, release=False)
            case "unlock": cmd_lock(root, agent, args.resource, "", release=True)
            case "add": cmd_add(root, agent, args.issue, args.lane)
            case "device": cmd_device(team_root(), agent, args.release)
    except Refused as refused:
        print(f"refused: {refused}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
