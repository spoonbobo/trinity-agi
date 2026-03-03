---
name: earnings-tracker
description: Track tech and AI earnings season automatically — weekly calendar previews, per-company scheduled alerts, and detailed post-earnings summaries delivered to your messaging channel.
homepage: https://github.com/trinityagi/trinity-agi
metadata:
  {
    "openclaw":
      {
        "emoji": "📈",
      },
  }
---

# Earnings Tracker

Automate earnings season tracking: weekly previews of upcoming reports, scheduled alerts for each earnings date, and detailed summaries after results drop.

## When to Activate

Trigger this skill when the user:
- Asks about upcoming earnings or earnings season
- Wants to track specific company earnings (e.g., NVDA, MSFT, GOOGL)
- Requests scheduled earnings alerts or summaries
- Mentions "earnings calendar", "quarterly results", or "earnings report"

## How It Works

### Phase 1: Weekly Preview (Sunday Cron)

Every Sunday, scan the upcoming week's earnings calendar and post relevant companies:

```bash
cron add "0 18 * * 0" "Search for this week's upcoming tech and AI earnings reports. Filter for companies I track. Post the list to my earnings channel and ask which ones I want detailed tracking for." --name "earnings-weekly-preview"
```

### Phase 2: Per-Earnings Scheduling

When the user confirms which companies to track, schedule one-shot cron jobs for each earnings date:

```bash
cron add "0 18 5 3 *" "NVDA earnings were today. Search for NVIDIA Q4 2026 earnings results and post a detailed summary." --delete-after-run --name "earnings-NVDA-Q4"
```

### Phase 3: Post-Earnings Summary

After each report drops, search for results and deliver a structured summary.

## Output Templates

### Weekly Preview

```
## Earnings Week Preview — [DATE RANGE]

Companies reporting this week that match your watchlist:

| Day | Company | Ticker | Expected | Time |
|-----|---------|--------|----------|------|
| Tue | NVIDIA | NVDA | EPS $0.89 | After close |
| Wed | Microsoft | MSFT | EPS $3.22 | After close |
| Thu | Amazon | AMZN | EPS $1.36 | After close |

Reply with which companies you want me to track in detail.
Companies I auto-suggest based on your history: NVDA, MSFT, GOOGL, META
```

### Post-Earnings Summary

```
## [COMPANY] Q[X] [YEAR] Earnings

**Result: BEAT / MISS / IN-LINE**

| Metric | Actual | Expected | Delta |
|--------|--------|----------|-------|
| Revenue | $XX.XB | $XX.XB | +X% |
| EPS | $X.XX | $X.XX | +X% |
| Gross Margin | XX% | XX% | +X pp |

### AI / Key Segment Highlights
- [Data center / AI revenue: $XXB, +XX% YoY]
- [Key product or segment performance]
- [Notable management commentary on AI]

### Guidance
- Q[X+1] revenue guidance: $XX-XXB (vs. $XXB expected)
- [Any notable forward-looking statements]

### Market Reaction
- After-hours move: +/-X%
- [Brief sentiment summary]
```

## Memory Integration

Store the user's tracked companies in memory:

```
Remember: I typically track these companies for earnings: NVDA, MSFT, GOOGL, META, AMZN, TSLA, AMD, AAPL, CRM, SNOW
```

Use this to auto-suggest companies each week without asking.

## Delivery

Send earnings updates via the user's preferred channel:
- **Telegram**: Best for mobile-first alerts
- **Discord**: Good for dedicated #earnings topic channels
- **Slack**: Works for team-shared earnings tracking

## Tips

- Use web search to get the **actual** earnings data — never fabricate numbers.
- Always include whether the company beat or missed expectations.
- AI/ML segment performance is especially relevant — always highlight data center and AI revenue when available.
- Schedule the post-earnings cron for a few hours after the expected report time to ensure results are published.
- Keep a running memory of which companies the user tracks so you can auto-suggest each week.
- If the user says "track all FAANG", expand that to the individual tickers.
