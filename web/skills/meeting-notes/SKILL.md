---
name: meeting-notes
description: Turn meeting transcripts into structured notes with action items, then optionally create tasks and post summaries to team channels.
homepage: https://github.com/trinityagi/trinity-agi
metadata:
  {
    "openclaw":
      {
        "emoji": "📋",
      },
  }
---

# Meeting Notes & Action Items

Parse any meeting transcript into structured notes, extract action items with owners and deadlines, and distribute them to project management tools and team channels.

## When to Activate

Trigger this skill when the user:
- Pastes a meeting transcript or points to a transcript file
- Asks for "meeting notes", "meeting summary", or "action items"
- Mentions processing a `.txt`, `.vtt`, or `.srt` transcript file
- Wants to summarize a call, standup, or discussion

## Input Modes

1. **Paste**: User pastes the transcript directly into chat.
2. **File path**: User provides a path to a `.txt`, `.vtt`, or `.srt` file.
3. **Folder watch** (automated): Set up a cron to monitor a folder for new transcripts.

### Reading VTT/SRT Files

VTT and SRT subtitle files from Zoom or Google Meet include timestamps and speaker labels.
Use these to attribute statements to specific people when extracting action items.

```bash
# Read a VTT file
cat ~/meeting-transcripts/standup-2026-03-03.vtt
```

## Output Template

Always structure meeting notes like this:

```
# Meeting Notes — [DATE]

## Attendees
[List of participants identified from the transcript]

## Key Decisions
1. [Decision 1] — [brief context]
2. [Decision 2] — [brief context]
3. [Decision 3] — [brief context]

## Action Items

| # | Task | Owner | Deadline | Status |
|---|------|-------|----------|--------|
| 1 | [What needs to be done] | [Person] | [Date or TBD] | Open |
| 2 | [What needs to be done] | [Person] | [Date or TBD] | Open |
| 3 | [What needs to be done] | [Person] | [Date or TBD] | Open |

## Discussion Summary
[3-5 bullet points covering the main topics discussed]

## Open Questions
- [Anything unresolved that needs follow-up]
```

## Post-Processing Actions

After generating notes, offer to:

### 1. Post Summary to a Channel
```
Send the meeting summary to #meeting-notes in Slack.
```
Use the slack or discord skill to post to the appropriate channel.

### 2. Create Tasks
If a task management skill is connected (Todoist, Trello, Notion, etc.), offer to create tickets for each action item:
- Assign to the right person
- Set the deadline
- Include context from the meeting

### 3. Set Follow-Up Reminders
For action items with deadlines, offer to schedule reminder crons:
```bash
cron add "0 9 * * *" "Check if [action item] is completed and ping [owner] if not" --delete-after-run --name "followup-[item]"
```

## Automated Pipeline (Folder Watch)

For teams that want hands-free processing:

```bash
cron add "*/30 * * * *" "Check ~/meeting-transcripts/ for new .txt or .vtt files. For each new file: parse into structured notes, create tasks, post summary to Slack, then move the file to ~/meeting-transcripts/processed/" --name "meeting-processor"
```

## Tips

- The real value is in **automatic task creation**, not just the summary. Meeting notes that don't become tracked tasks are documentation theater.
- VTT/SRT files with timestamps are better input than plain text — they help attribute statements to speakers.
- Match names from the transcript to real team members the user has mentioned before (check memory).
- When deadlines aren't explicitly mentioned, mark them as "TBD" — don't invent dates.
- Start simple (paste transcript, get summary) and automate incrementally.
- For long transcripts, focus on decisions and action items first, then provide the full summary.
