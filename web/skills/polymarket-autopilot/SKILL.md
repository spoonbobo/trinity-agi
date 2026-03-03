---
name: polymarket-autopilot
description: Paper-trade Polymarket prediction markets — scan for opportunities using TAIL, BONDING, and SPREAD strategies, simulate trades, and track portfolio performance.
metadata:
  {
    "openclaw":
      {
        "emoji": "📊",
        "requires": { "bins": ["uv"] },
        "os": ["darwin", "linux"],
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

# Polymarket Autopilot (Paper Trading)

Scan Polymarket prediction markets for opportunities and simulate trades without risking real money.
All market data is fetched from public APIs (no API keys or wallet required).

## Scan Markets

```bash
uv run {baseDir}/scripts/scan_markets.py --strategy all --limit 50
```

Filter by strategy:

```bash
uv run {baseDir}/scripts/scan_markets.py --strategy tail --min-volume 10000 --limit 30
uv run {baseDir}/scripts/scan_markets.py --strategy bonding --min-liquidity 5000
uv run {baseDir}/scripts/scan_markets.py --strategy spread --json
```

Flags: `--strategy tail|bonding|spread|all`, `--limit N`, `--min-volume N`, `--min-liquidity N`, `--json`.

## Paper Trade

Open a trade (requires token ID from scan output):

```bash
uv run {baseDir}/scripts/paper_trade.py \
  --market "Will BTC hit 100k by June?" \
  --token-id <clob_token_id> \
  --direction YES --amount 200 --strategy TAIL
```

Close a trade by ID:

```bash
uv run {baseDir}/scripts/paper_trade.py --close 1
```

List open trades:

```bash
uv run {baseDir}/scripts/paper_trade.py --list
```

Reset portfolio:

```bash
uv run {baseDir}/scripts/paper_trade.py --reset
```

Starting capital defaults to $10,000. Override with `--capital 50000` on first run.
Database: `~/.openclaw/workspace/polymarket-paper.db` (override with `--db`).

## Portfolio

```bash
uv run {baseDir}/scripts/portfolio.py
```

With live prices (fetches current CLOB midpoints for unrealised P&L):

```bash
uv run {baseDir}/scripts/portfolio.py --resolve
```

JSON output for programmatic use:

```bash
uv run {baseDir}/scripts/portfolio.py --resolve --format json
```

Show closed trade history:

```bash
uv run {baseDir}/scripts/portfolio.py --resolve --history
```

## Strategies

| Strategy | Logic | When to use |
|----------|-------|-------------|
| TAIL | Follow strong trends: probability > 60% or < 40% with volume | Momentum plays on clear favourites or underdogs |
| BONDING | Contrarian: wide bid-ask spread (>8%) signals overreaction | Buy uncertainty when markets panic |
| SPREAD | Arbitrage: YES + NO midpoints sum > 1.02 | Exploit mispriced complementary outcomes |

The scanner detects opportunities; you (or a cron) decide which trades to execute.

## Auto-Resolve Settled Markets

Check if any open paper trades have resolved and close them automatically:

```bash
uv run {baseDir}/scripts/resolve.py
```

Preview what would be resolved without changing the database:

```bash
uv run {baseDir}/scripts/resolve.py --dry-run
```

This enables a fully autonomous cron loop: scan -> trade -> resolve -> report.

## Backtest Strategies

Replay strategies against historical closed markets to tune thresholds:

```bash
uv run {baseDir}/scripts/backtest.py --limit 100 --bet-size 100
```

Test a specific strategy:

```bash
uv run {baseDir}/scripts/backtest.py --strategy tail --limit 200
```

JSON output with full signal details:

```bash
uv run {baseDir}/scripts/backtest.py --strategy all --limit 150 --json
```

Shows win rate, average P&L, top wins/losses, and simulated dollar returns per strategy.

## News Scanner

Cross-reference breaking news with open Polymarket markets:

```bash
uv run {baseDir}/scripts/news_scanner.py --limit 50
```

Custom RSS feeds:

```bash
uv run {baseDir}/scripts/news_scanner.py --feeds "https://feeds.bbci.co.uk/news/rss.xml,https://rss.nytimes.com/services/xml/rss/nyt/World.xml"
```

Lower the keyword match threshold for more results:

```bash
uv run {baseDir}/scripts/news_scanner.py --min-relevance 1 --json
```

Default feeds: BBC News, NYT, Reuters, Google News. No API keys required.

## Typical Workflow

1. Scan for opportunities: `uv run {baseDir}/scripts/scan_markets.py --json`
2. Check news for information edge: `uv run {baseDir}/scripts/news_scanner.py`
3. Open a paper trade: `uv run {baseDir}/scripts/paper_trade.py -m "..." -t <id> -d YES -a 100 -s TAIL`
4. Monitor: `uv run {baseDir}/scripts/portfolio.py --resolve`
5. Auto-close settled markets: `uv run {baseDir}/scripts/resolve.py`
6. Review performance: `uv run {baseDir}/scripts/portfolio.py --resolve --history`
7. Tune strategies with backtesting: `uv run {baseDir}/scripts/backtest.py --limit 200`

## Cron Setup

Schedule scans every 15 minutes using OpenClaw cron:

```bash
cron add "*/15 * * * *" "Scan Polymarket for opportunities and report findings. Use the polymarket-autopilot skill." --name "polymarket-scan"
```

Auto-resolve settled markets every hour:

```bash
cron add "0 * * * *" "Resolve any settled Polymarket paper trades using the polymarket-autopilot skill." --name "polymarket-resolve"
```

Daily morning summary at 8 AM:

```bash
cron add "0 8 * * *" "Show my Polymarket paper portfolio with live prices, resolve any settled trades, and post a summary." --name "polymarket-daily"
```

## Discord Reports

Post portfolio summaries to Discord using a webhook:

```bash
curl -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"$(uv run {baseDir}/scripts/portfolio.py --resolve 2>/dev/null)\"}"
```

Set `DISCORD_WEBHOOK_URL` in your environment or `openclaw.json`.

## Notes

- **Paper trading only.** No real money, no wallet keys, no on-chain transactions.
- Market data comes from Polymarket's public Gamma API and CLOB API (no authentication).
- News feeds are standard RSS/Atom (BBC, NYT, Reuters, Google News) -- no API keys.
- Database is local SQLite at `~/.openclaw/workspace/polymarket-paper.db`.
- Scanner makes ~2 API calls per market; use `--limit` to control scan breadth and rate.
- CLOB prices are real-time midpoints used for entry/exit pricing.
- The agent can compose these scripts freely -- scan, news, trade, resolve, backtest, review.
