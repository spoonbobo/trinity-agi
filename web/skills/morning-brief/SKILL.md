---
name: morning-brief
description: Schedule and deliver a personalized morning briefing every day — covering news, tasks, content drafts, and AI-recommended actions — via Telegram, Discord, iMessage, or any connected channel.
homepage: https://github.com/trinityagi/trinity-agi
metadata:
  {
    "openclaw":
      {
        "emoji": "📰",
      },
  }
---

# Morning Brief

Deliver a fully customized morning briefing at a scheduled time each day.
Uses web search, task integrations, and messaging channels already available in the gateway.

## When to Activate

Trigger this skill when the user asks for:
- A daily morning briefing or report
- Scheduled news digests
- "Send me a summary every morning"
- Automated daily updates on topics of interest

## How It Works

1. **Schedule a cron job** to run the briefing at the user's preferred time.
2. **Research** overnight news relevant to the user's interests using web search.
3. **Review tasks** if a task manager skill is connected (Todoist, Apple Reminders, Trello, etc.).
4. **Generate content drafts** — full outlines or scripts, not just titles.
5. **Recommend actions** the agent can complete autonomously that day.
6. **Deliver** via the user's preferred messaging channel.

## Setting Up the Cron

```bash
cron add "0 8 * * *" "Run my morning brief and send it to Telegram" --name "morning-brief"
```

Adjust the schedule to the user's preferred time and timezone.
Use `--session isolated` if the brief should run in its own session.

## Output Template

Structure every morning brief like this:

```
Good morning! Here's your brief for [DATE]:

## News & Trends
- [Headline 1]: [2-sentence summary + why it matters to you]
- [Headline 2]: [2-sentence summary + why it matters to you]
- [Headline 3]: [2-sentence summary + why it matters to you]

## Today's Tasks
- [ ] [Task 1] — [context/deadline]
- [ ] [Task 2] — [context/deadline]
- [ ] [Task 3] — [context/deadline]

## Content Drafts
### [Draft title]
[Full outline or script — not just a title]

## AI-Recommended Actions
Things I can handle for you today:
1. [Action 1] — [why and expected outcome]
2. [Action 2] — [why and expected outcome]

Reply to customize this brief or ask me to act on any recommendation.
```

## Customization

Users can modify the brief by texting naturally:

- "Add weather forecast to my morning brief"
- "Stop including general news, focus only on AI"
- "Include stock prices for NVDA and TSLA"
- "Add a motivational quote each morning"
- "Change delivery time to 7:30 AM"

Store preferences in memory so they persist across sessions.

## Delivering the Brief

Send via whatever messaging channel the user prefers:

- **Telegram**: Use the message tool with `channel: "telegram"`
- **Discord**: Use the message tool with `channel: "discord"`
- **iMessage**: Use the imsg skill if available
- **Slack**: Use the slack skill if available

## Tips

- The **AI-recommended actions** section is the most powerful part — proactively think of ways to help the user rather than waiting for instructions.
- Write **full drafts**, not just ideas. The user should wake up to finished work.
- If the user doesn't specify what to include, use judgment based on what you know about them from memory and past conversations.
- Keep news research focused on the user's stated interests. Default to tech/AI/startups if no preference is set.
- Use web search to get fresh, real-time information — never fabricate news.
