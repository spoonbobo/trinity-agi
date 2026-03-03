#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""
Generate a habit streak report with adaptive tone -- designed for cron delivery.

Outputs a human-readable report to stdout. The agent can relay this via
chat, Discord, Telegram, or any messaging channel.

Usage:
    uv run streak_report.py [--db path] [--days 7] [--json]
"""

import argparse
import json
import os
import sqlite3
import sys
from datetime import date, timedelta, timezone

DEFAULT_DB = os.path.expanduser("~/.openclaw/workspace/habit-tracker.db")


def get_db(db_path: str) -> sqlite3.Connection:
    """Open the habit tracker database (read-only)."""
    if not os.path.exists(db_path):
        print(f"Error: Database not found at {db_path}", file=sys.stderr)
        print("Run habit.py first to create habits.", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def is_due(frequency: str, target_date: str) -> bool:
    """Check if a habit is due on a given date."""
    d = date.fromisoformat(target_date)
    if frequency == "daily":
        return True
    if frequency == "weekday":
        return d.weekday() < 5
    if frequency == "weekly":
        return d.weekday() == 0
    return True


def compute_streak(conn: sqlite3.Connection, habit_id: int, frequency: str) -> tuple[int, int]:
    """Compute (current_streak, best_streak) for a habit."""
    rows = conn.execute(
        "SELECT date, status FROM completions WHERE habit_id = ? ORDER BY date DESC",
        (habit_id,),
    ).fetchall()

    if not rows:
        return 0, 0

    done_dates: set[str] = set()
    skipped_dates: set[str] = set()
    for r in rows:
        if r["status"] == "done":
            done_dates.add(r["date"])
        else:
            skipped_dates.add(r["date"])

    today = date.today()
    current_streak = 0
    d = today
    for _ in range(365):
        d_str = d.isoformat()
        if not is_due(frequency, d_str):
            d -= timedelta(days=1)
            continue
        if d_str in done_dates or d_str in skipped_dates:
            current_streak += 1
            d -= timedelta(days=1)
        else:
            if d == today:
                d -= timedelta(days=1)
                continue
            break

    all_dates = sorted(done_dates | skipped_dates)
    if not all_dates:
        return current_streak, current_streak

    first = date.fromisoformat(all_dates[0])
    last = date.fromisoformat(all_dates[-1])
    best_streak = 0
    streak = 0
    d = first
    while d <= last:
        d_str = d.isoformat()
        if not is_due(frequency, d_str):
            d += timedelta(days=1)
            continue
        if d_str in done_dates or d_str in skipped_dates:
            streak += 1
            best_streak = max(best_streak, streak)
        else:
            streak = 0
        d += timedelta(days=1)

    return current_streak, best_streak


def build_report(conn: sqlite3.Connection, days: int) -> dict:
    """Build a complete streak report."""
    habits = [dict(r) for r in conn.execute("SELECT * FROM habits ORDER BY name COLLATE NOCASE").fetchall()]

    if not habits:
        return {"error": "No habits found. Use habit.py add to create some."}

    today = date.today()
    since = (today - timedelta(days=days)).isoformat()
    today_str = today.isoformat()

    habit_reports = []
    total_due = 0
    total_done = 0
    total_missed = 0
    all_streaks_intact = True
    pending_today = []

    for h in habits:
        hid = h["id"]

        # Completion counts in window
        done_count = conn.execute(
            "SELECT COUNT(*) as c FROM completions WHERE habit_id = ? AND date >= ? AND status = 'done'",
            (hid, since),
        ).fetchone()["c"]

        skip_count = conn.execute(
            "SELECT COUNT(*) as c FROM completions WHERE habit_id = ? AND date >= ? AND status = 'skipped'",
            (hid, since),
        ).fetchone()["c"]

        # Due days in window
        due_days = 0
        d = today - timedelta(days=days)
        for _ in range(days + 1):
            if is_due(h["frequency"], d.isoformat()):
                due_days += 1
            d += timedelta(days=1)

        missed = max(0, due_days - done_count - skip_count)
        rate = done_count / due_days if due_days > 0 else 0.0
        current_streak, best_streak = compute_streak(conn, hid, h["frequency"])

        if missed > 0:
            all_streaks_intact = False

        total_due += due_days
        total_done += done_count
        total_missed += missed

        # Check if pending today
        today_comp = conn.execute(
            "SELECT * FROM completions WHERE habit_id = ? AND date = ?",
            (hid, today_str),
        ).fetchone()
        is_pending = today_comp is None and is_due(h["frequency"], today_str)
        if is_pending:
            pending_today.append(h["name"])

        habit_reports.append({
            "name": h["name"],
            "frequency": h["frequency"],
            "done": done_count,
            "skipped": skip_count,
            "due": due_days,
            "missed": missed,
            "rate": rate,
            "current_streak": current_streak,
            "best_streak": best_streak,
            "pending_today": is_pending,
        })

    overall_rate = total_done / total_due if total_due > 0 else 0.0

    # Determine tone
    if all_streaks_intact and overall_rate >= 0.9:
        tone = "excellent"
    elif overall_rate >= 0.7:
        tone = "good"
    elif overall_rate >= 0.4:
        tone = "needs_attention"
    else:
        tone = "struggling"

    return {
        "date": today_str,
        "period_days": days,
        "habits": habit_reports,
        "pending_today": pending_today,
        "overall_rate": overall_rate,
        "total_done": total_done,
        "total_due": total_due,
        "total_missed": total_missed,
        "tone": tone,
    }


def print_report(report: dict) -> None:
    """Print a human-readable streak report with adaptive tone."""
    if "error" in report:
        print(report["error"])
        return

    tone = report["tone"]
    rate = report["overall_rate"]

    # Adaptive header
    if tone == "excellent":
        header = "You're on fire! All streaks intact."
    elif tone == "good":
        header = "Solid progress. Keep it up!"
    elif tone == "needs_attention":
        header = "A few habits need your attention."
    else:
        header = "Let's get back on track -- one habit at a time."

    print(f"\n  {'='*55}")
    print(f"  HABIT REPORT -- {report['date']}")
    print(f"  {header}")
    print(f"  {'='*55}")
    print(f"  Overall: {report['total_done']}/{report['total_due']} completed ({rate:.0%}) over {report['period_days']} days")

    # Pending today
    if report["pending_today"]:
        print(f"\n  TODAY'S PENDING:")
        for name in report["pending_today"]:
            print(f"    [ ] {name}")

    # Per-habit breakdown
    print(f"\n  {'Habit':<22} {'Rate':>6} {'Streak':>7} {'Best':>6} {'Missed':>7}")
    print(f"  {'-'*55}")

    for h in report["habits"]:
        status_icon = "*" if h["pending_today"] else " "
        print(
            f"  {status_icon}{h['name']:<21} {h['rate']:>5.0%} {h['current_streak']:>6}d {h['best_streak']:>5}d {h['missed']:>6}"
        )

    # Motivational nudge
    print()
    if tone == "excellent":
        print("  Keep this momentum going!")
    elif tone == "good":
        missed_habits = [h["name"] for h in report["habits"] if h["missed"] > 0]
        if missed_habits:
            print(f"  Focus areas: {', '.join(missed_habits[:3])}")
    elif tone == "needs_attention":
        top_streak = max(report["habits"], key=lambda h: h["current_streak"])
        print(f"  Bright spot: \"{top_streak['name']}\" at {top_streak['current_streak']} day streak!")
    else:
        easiest = min(report["habits"], key=lambda h: h["due"])
        print(f"  Start small: just do \"{easiest['name']}\" today.")

    print()


def main():
    parser = argparse.ArgumentParser(description="Habit streak report generator")
    parser.add_argument("--db", default=DEFAULT_DB, help=f"SQLite database path (default: {DEFAULT_DB})")
    parser.add_argument("--days", type=int, default=7, help="Lookback period in days (default: 7)")
    parser.add_argument("--json", action="store_true", dest="output_json", help="Output JSON instead of human-readable report")

    args = parser.parse_args()
    conn = get_db(args.db)

    try:
        report = build_report(conn, args.days)
        if args.output_json:
            print(json.dumps(report, indent=2, default=str))
        else:
            print_report(report)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
