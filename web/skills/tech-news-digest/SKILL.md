---
name: tech-news-digest
description: Aggregate tech news from RSS feeds, GitHub releases, and web search into a scored, deduplicated digest. Use when asked for a tech news roundup, daily digest, or AI/open-source news summary.
homepage: https://github.com/hesamsheikh/awesome-openclaw-usecases
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

# Tech News Digest

Aggregate, deduplicate, and score tech news from multiple sources.

## Generate a digest

```bash
uv run {baseDir}/scripts/digest.py --hours 24 --max-items 30
```

Custom sources file (JSON):

```bash
uv run {baseDir}/scripts/digest.py --sources /path/to/sources.json --hours 48 --max-items 50
```

JSON output (for further processing):

```bash
uv run {baseDir}/scripts/digest.py --hours 24 --output json
```

## Sources

The script ships with 30+ built-in sources across three layers:

| Layer | Examples | Env var |
|-------|----------|---------|
| RSS feeds | Hacker News, OpenAI Blog, MIT Tech Review, Ars Technica, TechCrunch AI, The Verge | (none) |
| GitHub releases | vLLM, LangChain, Ollama, Dify, Open-WebUI, LiteLLM | `GITHUB_TOKEN` (optional, higher rate limit) |
| Web search | "AI breakthroughs", "open source LLM news" | `BRAVE_API_KEY` (optional) |

## Custom sources file

```json
{
  "rss": ["https://my-company-blog.com/feed"],
  "github": ["my-org/my-framework"],
  "search_queries": ["AI agents news this week"]
}
```

## Scoring

Priority source (+3), multi-source (+5), recency within 6h (+2), keyword relevance (+1). Duplicates merged by title similarity (Jaccard > 0.6).

## Delivery

Outputs markdown to stdout. To deliver via Discord or email, pipe through the `message` tool or `himalaya`.

## Cron

```text
Set up a daily tech digest at 9am: run the tech-news-digest script and send results here.
```

## API keys

- `BRAVE_API_KEY` — web search layer (optional)
- `GITHUB_TOKEN` — higher GitHub API rate limit (optional, 60 req/hr without)
- `X_BEARER_TOKEN` — reserved for future Twitter/X layer

## Notes

- Fully offline-capable with just RSS + GitHub (no keys needed).
- Use timestamps in filenames: `yyyy-mm-dd-digest.md`.
