---
name: habit-tracker
description: Track daily habits, maintain streaks, and get adaptive accountability nudges via scheduled check-ins. No API keys required.
metadata:
  {
    "openclaw":
      {
        "emoji": "✅",
        "requires": { "bins": ["uv"] },
        "install":
          [
            {
              "id": "uv-brew",
              "kind": "brew",
              "formula": "uv",
              "bins": ["uv"],
              "label": "Install uv (brew)",
            },
          ],
      },
  }
---

# Habit Tracker

Track daily habits, maintain streaks, and get accountability reports.
All data is stored locally in SQLite -- no API keys or accounts needed.

## Add Habits

```bash
uv run {baseDir}/scripts/habit.py add "Meditate" --frequency daily
uv run {baseDir}/scripts/habit.py add "Exercise" --frequency 3x-week
uv run {baseDir}/scripts/habit.py add "Read" --frequency weekday
uv run {baseDir}/scripts/habit.py add "Weekly review" --frequency weekly
```

Frequencies: `daily`, `weekday` (Mon-Fri), `weekly` (Mondays), `Nx-week` (e.g. `3x-week`).

## Daily Check-In

Mark habits as done:

```bash
uv run {baseDir}/scripts/habit.py check "Meditate" --note "10 min morning session"
uv run {baseDir}/scripts/habit.py check "Exercise"
```

Skip with a reason (preserves streak):

```bash
uv run {baseDir}/scripts/habit.py skip "Exercise" --reason "rest day"
```

Undo an entry:

```bash
uv run {baseDir}/scripts/habit.py undo "Meditate"
```

Backfill a past date:

```bash
uv run {baseDir}/scripts/habit.py check "Read" --date 2026-03-01
```

## List Today's Status

```bash
uv run {baseDir}/scripts/habit.py list
```

Check a specific date:

```bash
uv run {baseDir}/scripts/habit.py list --date 2026-03-01
```

## Stats & Streaks

```bash
uv run {baseDir}/scripts/habit.py stats
uv run {baseDir}/scripts/habit.py stats --habit "Meditate" --days 90
```

## Streak Report (for Cron)

```bash
uv run {baseDir}/scripts/streak_report.py --days 7
```

JSON output:

```bash
uv run {baseDir}/scripts/streak_report.py --days 30 --json
```

The report adapts its tone based on performance:
- All streaks intact: celebratory
- Most on track: encouraging with focus areas
- Several missed: highlights bright spots
- Struggling: suggests starting small

## Cron Setup

Morning check-in reminder at 8 AM:

```bash
cron add "0 8 * * *" "List my pending habits for today and remind me to complete them." --name "habit-morning"
```

Evening accountability at 9 PM:

```bash
cron add "0 21 * * *" "Generate my habit streak report for the last 7 days and give me feedback." --name "habit-evening"
```

Weekly review on Sundays:

```bash
cron add "0 10 * * 0" "Show my habit stats for the last 30 days with detailed streak analysis." --name "habit-weekly"
```

## Remove & Reset

```bash
uv run {baseDir}/scripts/habit.py remove "Meditate"
uv run {baseDir}/scripts/habit.py reset
```

## Notes

- Database: `~/.openclaw/workspace/habit-tracker.db` (override with `--db`).
- No API keys or external services required.
- Skipped days are tracked separately and do not break streaks.
- The agent can compose check-ins and reports freely in conversation.
