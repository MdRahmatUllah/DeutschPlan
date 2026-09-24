"""`tools/team.py`: the board parallel agents share.

Against a real (local, bare) origin, because the property that matters is
what happens when two agents push: the second one must re-read the first
one's board, not overwrite it.
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import team  # noqa: E402

BOARD = """# Tasks

Edited only through `python tools/team.py`.

## Tasks

| Issue | Ms | Lane | Pri | Size | Title | Status | Owner | Blocked by | PR |
|---|---|---|---|---|---|---|---|---|---|
| #10 | M4 | A | P1 | M | quiz builder | open |  | #1 |  |
| #11 | M4 | A | P1 | M | quiz sheet | open |  | #10 |  |
| #12 | M5 | B | P2 | S | search | open |  |  |  |

## Locks

| Resource | Owner | Since | Why |
|---|---|---|---|
| user-db-schema |  |  |  |

## Handoffs
"""


def run(*args: str, cwd: Path | None = None) -> None:
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=cwd, check=True, capture_output=True)


@pytest.fixture()
def team_repo(tmp_path: Path):
    origin = tmp_path / "origin.git"
    run("init", "--quiet", "--bare", "-b", "main", str(origin))
    seed = tmp_path / "seed"
    run("init", "--quiet", "-b", "team", str(seed))
    (seed / "TASKS.md").write_text(BOARD, encoding="utf-8", newline="\n")
    (seed / "MEMORY.md").write_text("# Memory\n\n", encoding="utf-8", newline="\n")
    (seed / "WORKLOG.md").write_text("# Work log\n\n", encoding="utf-8", newline="\n")
    (seed / "agents").mkdir()
    (seed / "agents" / ".keep").write_text("", encoding="utf-8")
    run("add", "-A", cwd=seed)
    run("commit", "--quiet", "-m", "board", cwd=seed)
    run("push", "--quiet", str(origin), "team", cwd=seed)

    roots = {}
    for agent in ("agent-1", "agent-2"):
        root = tmp_path / agent
        run("clone", "--quiet", "--branch", "team", str(origin), str(root))
        team.cmd_join(root, agent, force=False)
        roots[agent] = root
    return roots


def board(root: Path) -> team.Board:
    team.sync(root)
    return team.Board((root / "TASKS.md").read_text(encoding="utf-8"))


def test_a_claim_is_recorded_everywhere_it_should_be(team_repo):
    a1 = team_repo["agent-1"]
    team.cmd_claim(a1, "agent-1", 12)
    task = board(team_repo["agent-2"]).task(12)
    assert (task.status, task.owner) == ("in-progress", "agent-1")
    assert "#12 search" in (a1 / "agents" / "agent-1.md").read_text(encoding="utf-8")
    assert "agent-1 #12 · claimed: search" in (a1 / "WORKLOG.md").read_text(encoding="utf-8")
    assert "#12 in-progress · agent-1" in (a1 / "STATUS.md").read_text(encoding="utf-8")


def test_two_agents_cannot_claim_the_same_issue(team_repo):
    team.cmd_claim(team_repo["agent-1"], "agent-1", 12)
    # agent-2's clone has not seen that claim; the transaction re-reads first.
    with pytest.raises(team.Refused, match="in-progress"):
        team.cmd_claim(team_repo["agent-2"], "agent-2", 12)


def test_a_push_that_loses_the_race_is_re_checked_against_the_winner(team_repo):
    a1, a2 = team_repo["agent-1"], team_repo["agent-2"]
    attempts = []

    def racing(root, board):
        if not attempts:
            # agent-1's claim lands between agent-2's read and agent-2's push.
            team.cmd_claim(a1, "agent-1", 12)
        attempts.append(board.task(12).status)
        task = board.task(12)
        if task.status != "open":
            raise team.Refused(f"#12 is {task.status}")
        task.status, task.owner = "in-progress", "agent-2"

    with pytest.raises(team.Refused):
        team.transact(a2, "agent-2", "race", team.on_board(racing))
    assert attempts == ["open", "in-progress"]
    assert board(a2).task(12).owner == "agent-1"


def test_blocked_work_waits_for_its_blockers(team_repo):
    a1 = team_repo["agent-1"]
    team.cmd_claim(a1, "agent-1", 10)  # #1 is not on the board: closed already
    with pytest.raises(team.Refused, match="blocked by #10"):
        team.cmd_claim(team_repo["agent-2"], "agent-2", 11)
    team.cmd_done(a1, "agent-1", 10, pr=99, message="", check_closed=lambda _: True)
    team.cmd_claim(team_repo["agent-2"], "agent-2", 11)
    report = (a1 / "TASKS.md").read_text(encoding="utf-8")
    assert "#10 (quiz builder) is merged as #99. Now ready: #11." in report


def test_done_waits_for_github_to_close_the_issue(team_repo):
    team.cmd_claim(team_repo["agent-1"], "agent-1", 12)
    with pytest.raises(team.Refused, match="still open on GitHub"):
        team.cmd_done(team_repo["agent-1"], "agent-1", 12, pr=None, message="", check_closed=lambda _: False)


def test_a_forgotten_done_is_flagged_and_anyone_can_record_it(team_repo, capsys):
    a1, a2 = team_repo["agent-1"], team_repo["agent-2"]
    team.cmd_claim(a1, "agent-1", 10)
    team.cmd_review(a1, "agent-1", 10, pr=7, to="all")
    capsys.readouterr()
    team.cmd_status(a2, "agent-2", closed=lambda n: n == 10)
    assert "#10 is closed on GitHub but review here (agent-1)" in capsys.readouterr().out
    team.cmd_done(a2, "agent-2", 10, pr=None, message="", check_closed=lambda _: True)
    assert board(a2).task(10).status == "done"
    assert "(Recorded by agent-2 for agent-1.)" in (a2 / "TASKS.md").read_text(encoding="utf-8")


def test_hand_edits_to_the_plan_are_never_reset_away(team_repo):
    a1 = team_repo["agent-1"]
    team.sync(a1)
    (a1 / "PLAN.md").write_text("# plan\n", encoding="utf-8")
    team.git(a1, "add", "PLAN.md")
    team.git(a1, "commit", "-qm", "plan")
    team.git(a1, "push", "-q", "origin", "HEAD:team")
    (a1 / "PLAN.md").write_text("# plan, edited\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="PLAN.md has edits that are not pushed"):
        team.cmd_claim(a1, "agent-1", 12)
    assert (a1 / "PLAN.md").read_text(encoding="utf-8") == "# plan, edited\n"


def test_one_task_in_progress_at_a_time(team_repo):
    a1 = team_repo["agent-1"]
    team.cmd_claim(a1, "agent-1", 12)
    with pytest.raises(team.Refused, match="already have #12"):
        team.cmd_claim(a1, "agent-1", 10)
    team.cmd_review(a1, "agent-1", 12, pr=5, to="all")
    team.cmd_claim(a1, "agent-1", 10)  # a PR in review does not hold the agent


def test_assignments_and_reports_reach_the_other_agent(team_repo):
    a1, a2 = team_repo["agent-1"], team_repo["agent-2"]
    team.cmd_assign(a1, "agent-1", 12, "agent-2", "yours: it continues my search work")
    with pytest.raises(team.Refused, match="assigned to agent-2"):
        team.cmd_claim(a1, "agent-1", 12)
    team.sync(a2)
    unread = team.handoffs_for((a2 / "TASKS.md").read_text(encoding="utf-8"), "agent-2", 0)
    assert len(unread) == 1 and "agent-1 → agent-2 · assign · #12" in unread[0]
    team.cmd_ack(a2, "agent-2")
    latest = team.read_field((a2 / "agents" / "agent-2.md").read_text(encoding="utf-8"), "last-read")
    assert team.handoffs_for((a2 / "TASKS.md").read_text(encoding="utf-8"), "agent-2", int(latest)) == []
    team.cmd_claim(a2, "agent-2", 12)


def test_the_board_keeps_its_prose_and_every_handoff(team_repo):
    a1 = team_repo["agent-1"]
    team.cmd_msg(a1, "agent-1", "all", "heads-up", "changing AdaptiveScaffold", None)
    team.cmd_msg(a1, "agent-1", "agent-2", "question", "is #12 yours?", 12)
    text = (a1 / "TASKS.md").read_text(encoding="utf-8")
    assert "Edited only through" in text
    assert "### H-1 " in text and "### H-2 " in text
    assert len(team.Board(text).tasks) == 3


def test_a_lock_has_one_holder(team_repo):
    team.cmd_lock(team_repo["agent-1"], "agent-1", "user-db-schema", "migration 7", release=False)
    with pytest.raises(team.Refused, match="held by agent-1"):
        team.cmd_lock(team_repo["agent-2"], "agent-2", "user-db-schema", "mine", release=False)
    team.cmd_lock(team_repo["agent-1"], "agent-1", "user-db-schema", "", release=True)
    team.cmd_lock(team_repo["agent-2"], "agent-2", "user-db-schema", "mine", release=False)


def test_an_active_identity_is_not_taken_twice(team_repo):
    a1 = team_repo["agent-1"]
    with pytest.raises(team.Refused, match="looks active"):
        team.cmd_join(a1, "agent-1", force=False)
    team.cmd_leave(a1, "agent-1", "PR #5 waits on CI")
    team.cmd_join(a1, "agent-1", force=False)
    memory = (a1 / "agents" / "agent-1.md").read_text(encoding="utf-8")
    assert "PR #5 waits on CI" in memory


def test_memory_and_notes_are_appended(team_repo):
    a1 = team_repo["agent-1"]
    team.transact(a1, "agent-1", "remember", lambda r: team.remember(r, "agent-1", "drift", "customStatement does not notify watchers"))
    team.transact(a1, "agent-1", "note", lambda r: team.set_section(r, "agent-1", "Memory", "- worktree dp-wt/agent-1", append=True))
    team.transact(a1, "agent-1", "note", lambda r: team.set_section(r, "agent-1", "Memory", "- branch feat/12", append=True))
    assert "**drift** " in (a1 / "MEMORY.md").read_text(encoding="utf-8")
    memory = (a1 / "agents" / "agent-1.md").read_text(encoding="utf-8")
    assert "- worktree dp-wt/agent-1\n- branch feat/12" in memory


def test_the_device_has_one_holder_until_the_lock_goes_stale(tmp_path):
    team.cmd_device(tmp_path, "agent-1", release=False)
    with pytest.raises(team.Refused, match="in use by agent-1"):
        team.cmd_device(tmp_path, "agent-2", release=False)
    with pytest.raises(team.Refused, match="not you"):
        team.cmd_device(tmp_path, "agent-2", release=True)
    old = time.time() - team.DEVICE_LOCK_STALE_SECONDS - 60
    os.utime(tmp_path / ".device.lock", (old, old))
    team.cmd_device(tmp_path, "agent-2", release=False)  # breaks the stale one
    team.cmd_device(tmp_path, "agent-2", release=True)
    assert not (tmp_path / ".device.lock").exists()


def test_identities_run_from_the_lead_to_agent_9():
    for good in ("agent-0", "agent-1", "agent-9"):
        assert team.check_agent(good) == good
    for bad in ("agent-10", "agent", "Agent-1", "agent-01", "owner"):
        with pytest.raises(SystemExit):
            team.check_agent(bad)


def test_a_github_issue_becomes_a_row():
    data = {
        "title": "L7 · Custom quiz sheet",
        "milestone": {"title": "M4 · Quiz & mock exams"},
        "labels": [{"name": "P1"}, {"name": "size:M"}, {"name": "feature"}],
        "body": "## Goal\nx\n\n## Dependencies\nBlocked by #81, #116, #37\n\n---\nfooter #999",
    }
    task = team.task_from_issue(122, data, "A")
    assert (task.ms, task.pri, task.size, task.blocked_by) == ("M4", "P1", "M", [37, 81, 116])
    assert task.row().startswith("| #122 | M4 | A | P1 | M | L7 · Custom quiz sheet | open |")


def test_status_prints_the_board_on_a_cp1252_console(team_repo, monkeypatch):
    """A Windows console is cp1252; the board has arrows, dots and Bangla."""
    import io
    a1, a2 = team_repo["agent-1"], team_repo["agent-2"]
    team.cmd_msg(a1, "agent-1", "agent-2", "note", "বাংলা → fine · yes", None)
    raw = io.BytesIO()
    console = io.TextIOWrapper(raw, encoding="cp1252")
    monkeypatch.setattr(sys, "stdout", console)
    monkeypatch.setattr(team, "my_agent", lambda: "agent-2")
    monkeypatch.setattr(team, "board_checkout", lambda agent: a2)
    assert team.main(["status"]) == 0
    console.flush()
    assert "বাংলা → fine" in raw.getvalue().decode("utf-8")
