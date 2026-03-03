#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""
Habit tracker CLI -- add, check off, skip, list, and review daily habits.

All data is stored in a local SQLite database.

Usage:
    uv run habit.py add "Meditate" [--frequency daily|weekday|weekly|Nx-week]
    uv run habit.py check "Meditate" [--note "10 min session"] [--date 2026-03-03]
    uv run habit.py skip "Meditate" --reason "sick" [--date 2026-03-03]
    uv run habit.py undo "Meditate" [--date 2026-03-03]
    uv run habit.py list [--date 2026-03-03]
    uv run habit.py stats [--habit "Meditate"] [--days 30]
    uv run habit.py remove "Meditate"
    uv run habit.py reset
"""

import argparse
import os
import re
import sqlite3
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

DEFAULT_DB = os.path.expanduser("~/.openclaw/workspace/habit-tracker.db")


def get_db(db_path: str) -> sqlite3.Connection:
    """Open and initialise the habit tracker database."""
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS habits (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT NOT NULL UNIQUE COLLATE NOCASE,
            frequency   TEXT NOT NULL DEFAULT 'daily',
            created_at  TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS completions (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            habit_id    INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
            date        TEXT NOT NULL,
            status      TEXT NOT NULL CHECK (status IN ('done', 'skipped')),
            note        TEXT,
            created_at  TEXT NOT NULL,
            UNIQUE(habit_id, date)
        );
    """)
    conn.commit()
    return conn


def parse_date(date_str: str | None) -> str:
    """Parse a date string or return today's date."""
    if not date_str:
        return date.today().isoformat()
    try:
        return date.fromisoformat(date_str).isoformat()
    except ValueError:
        print(f"Error: Invalid date format '{date_str}'. Use YYYY-MM-DD.", file=sys.stderr)
        sys.exit(1)


def parse_frequency(freq: str) -> str:
    """Validate and normalise frequency string."""
    freq = freq.lower().strip()
    if freq in ("daily", "weekday", "weekly"):
        return freq
    match = re.match(r"^(\d+)x[- ]?week$", freq)
    if match:
        n = int(match.group(1))
        if 1 <= n <= 7:
            return f"{n}x-week"
    print(f"Error: Invalid frequency '{freq}'.", file=sys.stderr)
    print("  Valid: daily, weekday, weekly, Nx-week (e.g. 3x-week)", file=sys.stderr)
    sys.exit(1)


def get_habit(conn: sqlite3.Connection, name: str) -> dict | None:
    """Look up a habit by name (case-insensitive)."""
    row = conn.execute("SELECT * FROM habits WHERE name = ? COLLATE NOCASE", (name,)).fetchone()
    return dict(row) if row else None


def is_due(frequency: str, target_date: str) -> bool:
    """Check if a habit is due on a given date based on its frequency."""
    d = date.fromisoformat(target_date)
    if frequency == "daily":
        return True
    if frequency == "weekday":
        return d.weekday() < 5  # Mon-Fri
    if frequency == "weekly":
        return d.weekday() == 0  # Monday
    # Nx-week: always considered "due" (tracked at week level)
    return True


def cmd_add(conn: sqlite3.Connection, name: str, frequency: str) -> None:
    """Add a new habit."""
    freq = parse_frequency(frequency)
    now = datetime.now(timezone.utc).isoformat()
    try:
        conn.execute(
            "INSERT INTO habits (name, frequency, created_at) VALUES (?, ?, ?)",
            (name, freq, now),
        )
        conn.commit()
        print(f"Habit added: \"{name}\" ({freq})")
    except sqlite3.IntegrityError:
        print(f"Error: Habit \"{name}\" already exists.", file=sys.stderr)
        sys.exit(1)


def cmd_check(conn: sqlite3.Connection, name: str, target_date: str, note: str | None) -> None:
    """Mark a habit as done for a date."""
    habit = get_habit(conn, name)
    if not habit:
        print(f"Error: Habit \"{name}\" not found.", file=sys.stderr)
        sys.exit(1)

    now = datetime.now(timezone.utc).isoformat()
    try:
        conn.execute(
            "INSERT INTO completions (habit_id, date, status, note, created_at) VALUES (?, ?, 'done', ?, ?)",
            (habit["id"], target_date, note, now),
        )
        conn.commit()
        note_str = f" -- {note}" if note else ""
        print(f"Done: \"{name}\" for {target_date}{note_str}")
    except sqlite3.IntegrityError:
        # Update existing entry
        conn.execute(
            "UPDATE completions SET status = 'done', note = ?, created_at = ? WHERE habit_id = ? AND date = ?",
            (note, now, habit["id"], target_date),
        )
        conn.commit()
        print(f"Updated: \"{name}\" for {target_date} -> done")


def cmd_skip(conn: sqlite3.Connection, name: str, target_date: str, reason: str | None) -> None:
    """Mark a habit as intentionally skipped (doesn't break streak)."""
    habit = get_habit(conn, name)
    if not habit:
        print(f"Error: Habit \"{name}\" not found.", file=sys.stderr)
        sys.exit(1)

    now = datetime.now(timezone.utc).isoformat()
    try:
        conn.execute(
            "INSERT INTO completions (habit_id, date, status, note, created_at) VALUES (?, ?, 'skipped', ?, ?)",
            (habit["id"], target_date, reason, now),
        )
        conn.commit()
        reason_str = f" -- {reason}" if reason else ""
        print(f"Skipped: \"{name}\" for {target_date}{reason_str}")
    except sqlite3.IntegrityError:
        conn.execute(
            "UPDATE completions SET status = 'skipped', note = ?, created_at = ? WHERE habit_id = ? AND date = ?",
            (reason, now, habit["id"], target_date),
        )
        conn.commit()
        print(f"Updated: \"{name}\" for {target_date} -> skipped")


def cmd_undo(conn: sqlite3.Connection, name: str, target_date: str) -> None:
    """Remove a completion entry for a date."""
    habit = get_habit(conn, name)
    if not habit:
        print(f"Error: Habit \"{name}\" not found.", file=sys.stderr)
        sys.exit(1)

    result = conn.execute(
        "DELETE FROM completions WHERE habit_id = ? AND date = ?",
        (habit["id"], target_date),
    )
    conn.commit()
    if result.rowcount > 0:
        print(f"Undone: \"{name}\" for {target_date}")
    else:
        print(f"Nothing to undo for \"{name}\" on {target_date}.")


def cmd_list(conn: sqlite3.Connection, target_date: str) -> None:
    """List all habits with their status for a given date."""
    habits = conn.execute("SELECT * FROM habits ORDER BY name COLLATE NOCASE").fetchall()
    if not habits:
        print("No habits tracked yet. Use 'add' to create one.")
        return

    day_name = date.fromisoformat(target_date).strftime("%A")
    print(f"\n  Habits for {target_date} ({day_name})")
    print(f"  {'-'*50}")

    for h in habits:
        comp = conn.execute(
            "SELECT * FROM completions WHERE habit_id = ? AND date = ?",
            (h["id"], target_date),
        ).fetchone()

        due = is_due(h["frequency"], target_date)

        if comp:
            status = "DONE" if comp["status"] == "done" else "SKIP"
            note = f"  ({comp['note']})" if comp["note"] else ""
            marker = "[x]" if status == "DONE" else "[-]"
        elif due:
            status = "PENDING"
            note = ""
            marker = "[ ]"
        else:
            status = "N/A"
            note = "(not due)"
            marker = "   "

        print(f"  {marker} {h['name']:<25} {h['frequency']:<10} {status}{note}")

    print()


def compute_streak(conn: sqlite3.Connection, habit_id: int, frequency: str) -> tuple[int, int]:
    """Compute current streak and best streak for a habit. Returns (current, best)."""
    rows = conn.execute(
        "SELECT date, status FROM completions WHERE habit_id = ? ORDER BY date DESC",
        (habit_id,),
    ).fetchall()

    if not rows:
        return 0, 0

    # Build a set of completed dates and skipped dates
    done_dates: set[str] = set()
    skipped_dates: set[str] = set()
    for r in rows:
        if r["status"] == "done":
            done_dates.add(r["date"])
        else:
            skipped_dates.add(r["date"])

    # Walk backwards from today to compute current streak
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
            # If today and not yet checked off, don't count as broken
            if d == today:
                d -= timedelta(days=1)
                continue
            break

    # Walk all dates for best streak
    if not done_dates and not skipped_dates:
        return 0, 0

    all_dates = sorted(done_dates | skipped_dates)
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


def cmd_stats(conn: sqlite3.Connection, habit_name: str | None, days: int) -> None:
    """Show stats for one or all habits."""
    if habit_name:
        habit = get_habit(conn, habit_name)
        if not habit:
            print(f"Error: Habit \"{habit_name}\" not found.", file=sys.stderr)
            sys.exit(1)
        habits = [habit]
    else:
        habits = [dict(r) for r in conn.execute("SELECT * FROM habits ORDER BY name COLLATE NOCASE").fetchall()]

    if not habits:
        print("No habits tracked yet.")
        return

    since = (date.today() - timedelta(days=days)).isoformat()

    print(f"\n  {'='*60}")
    print(f"  HABIT STATS (last {days} days)")
    print(f"  {'='*60}")

    for h in habits:
        done_count = conn.execute(
            "SELECT COUNT(*) as c FROM completions WHERE habit_id = ? AND date >= ? AND status = 'done'",
            (h["id"], since),
        ).fetchone()["c"]

        skip_count = conn.execute(
            "SELECT COUNT(*) as c FROM completions WHERE habit_id = ? AND date >= ? AND status = 'skipped'",
            (h["id"], since),
        ).fetchone()["c"]

        # Count due days in the period
        due_days = 0
        d = date.today() - timedelta(days=days)
        for _ in range(days + 1):
            if is_due(h["frequency"], d.isoformat()):
                due_days += 1
            d += timedelta(days=1)

        rate = done_count / due_days if due_days > 0 else 0.0
        current_streak, best_streak = compute_streak(conn, h["id"], h["frequency"])

        print(f"\n  {h['name']}  ({h['frequency']})")
        print(f"  {'-'*40}")
        print(f"    Completed:      {done_count}/{due_days} ({rate:.0%})")
        print(f"    Skipped:        {skip_count}")
        print(f"    Current streak: {current_streak} days")
        print(f"    Best streak:    {best_streak} days")

    print()


def cmd_remove(conn: sqlite3.Connection, name: str) -> None:
    """Remove a habit and all its completions."""
    habit = get_habit(conn, name)
    if not habit:
        print(f"Error: Habit \"{name}\" not found.", file=sys.stderr)
        sys.exit(1)

    conn.execute("DELETE FROM completions WHERE habit_id = ?", (habit["id"],))
    conn.execute("DELETE FROM habits WHERE id = ?", (habit["id"],))
    conn.commit()
    print(f"Removed habit \"{name}\" and all its data.")


def cmd_reset(conn: sqlite3.Connection) -> None:
    """Wipe all data."""
    conn.executescript("DELETE FROM completions; DELETE FROM habits;")
    conn.commit()
    print("All habits and completions deleted.")


def main():
    parser = argparse.ArgumentParser(description="Habit tracker CLI")
    parser.add_argument("--db", default=DEFAULT_DB, help=f"SQLite database path (default: {DEFAULT_DB})")
    sub = parser.add_subparsers(dest="command", required=True)

    # add
    p_add = sub.add_parser("add", help="Add a new habit")
    p_add.add_argument("name", help="Habit name")
    p_add.add_argument("--frequency", "-f", default="daily", help="daily, weekday, weekly, or Nx-week (default: daily)")

    # check
    p_check = sub.add_parser("check", help="Mark a habit as done")
    p_check.add_argument("name", help="Habit name")
    p_check.add_argument("--note", "-n", help="Optional note")
    p_check.add_argument("--date", "-d", dest="target_date", help="Date (YYYY-MM-DD, default: today)")

    # skip
    p_skip = sub.add_parser("skip", help="Mark a habit as skipped")
    p_skip.add_argument("name", help="Habit name")
    p_skip.add_argument("--reason", "-r", help="Reason for skipping")
    p_skip.add_argument("--date", "-d", dest="target_date", help="Date (YYYY-MM-DD, default: today)")

    # undo
    p_undo = sub.add_parser("undo", help="Undo a completion for a date")
    p_undo.add_argument("name", help="Habit name")
    p_undo.add_argument("--date", "-d", dest="target_date", help="Date (YYYY-MM-DD, default: today)")

    # list
    p_list = sub.add_parser("list", help="List habits with status for a date")
    p_list.add_argument("--date", "-d", dest="target_date", help="Date (YYYY-MM-DD, default: today)")

    # stats
    p_stats = sub.add_parser("stats", help="Show habit statistics")
    p_stats.add_argument("--habit", help="Specific habit name (default: all)")
    p_stats.add_argument("--days", type=int, default=30, help="Lookback period in days (default: 30)")

    # remove
    p_rm = sub.add_parser("remove", help="Remove a habit")
    p_rm.add_argument("name", help="Habit name")

    # reset
    sub.add_parser("reset", help="Delete all habits and data")

    args = parser.parse_args()
    conn = get_db(args.db)

    try:
        if args.command == "add":
            cmd_add(conn, args.name, args.frequency)
        elif args.command == "check":
            cmd_check(conn, args.name, parse_date(args.target_date), args.note)
        elif args.command == "skip":
            cmd_skip(conn, args.name, parse_date(args.target_date), args.reason)
        elif args.command == "undo":
            cmd_undo(conn, args.name, parse_date(args.target_date))
        elif args.command == "list":
            cmd_list(conn, parse_date(args.target_date))
        elif args.command == "stats":
            cmd_stats(conn, args.habit, args.days)
        elif args.command == "remove":
            cmd_remove(conn, args.name)
        elif args.command == "reset":
            cmd_reset(conn)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
