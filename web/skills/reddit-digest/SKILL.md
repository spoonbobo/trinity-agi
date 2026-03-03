---
name: reddit-digest
description: Fetch and summarize top posts from your favorite subreddits using Reddit's public JSON API -- no API key or account required.
metadata:
  {
    "openclaw":
      {
        "emoji": "📰",
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

# Reddit Digest

Fetch top posts from any subreddit via Reddit's public JSON API.
No API key, no account, no authentication required.

## Quick Start

```bash
uv run {baseDir}/scripts/fetch_reddit.py --subreddits "python,machinelearning"
```

## Multiple Subreddits

```bash
uv run {baseDir}/scripts/fetch_reddit.py -s "selfhosted,homelab,LocalLLaMA,singularity"
```

## Sort & Filter

Top posts from the past week with at least 100 upvotes:

```bash
uv run {baseDir}/scripts/fetch_reddit.py -s "worldnews" --sort top --time week --min-score 100
```

Rising posts (good for catching trends early):

```bash
uv run {baseDir}/scripts/fetch_reddit.py -s "technology" --sort rising --limit 5
```

New posts:

```bash
uv run {baseDir}/scripts/fetch_reddit.py -s "programming" --sort new --limit 15
```

## With Comments

Fetch top 3 comments per post for richer context:

```bash
uv run {baseDir}/scripts/fetch_reddit.py -s "AskReddit" --limit 5 --include-comments
```

## JSON Output

```bash
uv run {baseDir}/scripts/fetch_reddit.py -s "python" --sort top --time day --json
```

## Cron Setup

Daily morning digest at 7 AM:

```bash
cron add "0 7 * * *" "Fetch my Reddit digest from r/selfhosted, r/LocalLLaMA, r/machinelearning (top posts, last 24h, min 50 upvotes) and summarize the most interesting posts." --name "reddit-morning"
```

Weekly deep dive on Saturdays:

```bash
cron add "0 9 * * 6" "Fetch top posts from r/programming, r/python, r/golang for the past week (min 200 upvotes, include comments) and write a summary of key discussions." --name "reddit-weekly"
```

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--subreddits, -s` | (required) | Comma-separated subreddit list |
| `--sort` | `hot` | `hot`, `top`, `new`, `rising` |
| `--time, -t` | `day` | Time window for `top`: `hour`, `day`, `week`, `month`, `year`, `all` |
| `--limit, -l` | `10` | Posts per subreddit |
| `--min-score` | `0` | Minimum upvotes to include |
| `--include-comments, -c` | off | Fetch top 3 comments per post |
| `--json` | off | Raw JSON output |

## Notes

- Uses Reddit's public `.json` endpoints (no OAuth, no API key).
- Rate-limited to ~1 request/second to respect Reddit's limits.
- Stickied/pinned posts are automatically excluded.
- The agent can summarise the digest further in conversation.
- For private or quarantined subreddits, the public API will return empty results.
