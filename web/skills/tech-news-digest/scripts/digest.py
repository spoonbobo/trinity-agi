#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "feedparser>=6.0.0",
#     "requests>=2.28.0",
# ]
# ///
"""
Aggregate tech news from RSS feeds, GitHub releases, and Brave web search.

Usage:
    uv run digest.py --hours 24 --max-items 30
    uv run digest.py --sources sources.json --hours 48 --output json
"""

import argparse
import json
import os
import sys
import re
from datetime import datetime, timezone, timedelta
from pathlib import Path


# ── Built-in default sources ────────────────────────────────────────────

DEFAULT_RSS = [
    # Hacker News
    "https://hnrss.org/frontpage?count=30",
    # AI / ML
    "https://openai.com/blog/rss.xml",
    "https://blog.google/technology/ai/rss/",
    "https://ai.meta.com/blog/rss/",
    "https://www.anthropic.com/rss.xml",
    "https://huggingface.co/blog/feed.xml",
    # Tech news
    "https://techcrunch.com/category/artificial-intelligence/feed/",
    "https://www.theverge.com/rss/index.xml",
    "https://arstechnica.com/feed/",
    "https://feeds.arstechnica.com/arstechnica/technology-lab",
    "https://www.technologyreview.com/feed/",
    "https://www.wired.com/feed/rss",
    # Dev / open source
    "https://github.blog/feed/",
    "https://news.ycombinator.com/rss",
    "https://lobste.rs/rss",
    "https://dev.to/feed",
]

DEFAULT_GITHUB = [
    "vllm-project/vllm",
    "langchain-ai/langchain",
    "ollama/ollama",
    "langgenius/dify",
    "open-webui/open-webui",
    "BerriAI/litellm",
    "huggingface/transformers",
    "ggml-org/llama.cpp",
    "lm-sys/FastChat",
    "run-llama/llama_index",
    "microsoft/autogen",
    "significant-gravitas/AutoGPT",
    "crewAIInc/crewAI",
    "mem0ai/mem0",
    "pydantic/pydantic-ai",
]

DEFAULT_SEARCH_QUERIES = [
    "AI breakthroughs this week",
    "open source LLM news",
]

PRIORITY_DOMAINS = {
    "openai.com", "anthropic.com", "blog.google", "ai.meta.com",
    "huggingface.co", "github.blog", "technologyreview.com",
}

RELEVANT_KEYWORDS = {
    "ai", "llm", "gpt", "claude", "gemini", "transformer", "agent",
    "open-source", "machine learning", "deep learning", "neural",
    "diffusion", "rag", "fine-tuning", "inference", "gpu", "cuda",
    "langchain", "ollama", "vllm", "huggingface",
}


def load_sources(sources_path: str | None) -> dict:
    """Load sources from JSON file or return defaults."""
    if sources_path:
        with open(sources_path) as f:
            custom = json.load(f)
        return {
            "rss": custom.get("rss", []),
            "github": custom.get("github", []),
            "search_queries": custom.get("search_queries", []),
        }
    return {
        "rss": DEFAULT_RSS,
        "github": DEFAULT_GITHUB,
        "search_queries": DEFAULT_SEARCH_QUERIES,
    }


# ── RSS layer ───────────────────────────────────────────────────────────

def fetch_rss(feeds: list[str], cutoff: datetime) -> list[dict]:
    import feedparser

    articles = []
    for url in feeds:
        try:
            feed = feedparser.parse(url)
            for entry in feed.entries[:20]:
                published = None
                for field in ("published_parsed", "updated_parsed"):
                    ts = getattr(entry, field, None)
                    if ts:
                        from time import mktime
                        published = datetime.fromtimestamp(mktime(ts), tz=timezone.utc)
                        break
                if not published:
                    published = datetime.now(timezone.utc)

                if published < cutoff:
                    continue

                link = getattr(entry, "link", "")
                articles.append({
                    "title": getattr(entry, "title", "Untitled"),
                    "url": link,
                    "source": feed.feed.get("title", url),
                    "published": published.isoformat(),
                    "layer": "rss",
                })
        except Exception as e:
            print(f"[rss] Error fetching {url}: {e}", file=sys.stderr)
    return articles


# ── GitHub releases layer ───────────────────────────────────────────────

def fetch_github_releases(repos: list[str], cutoff: datetime) -> list[dict]:
    import requests

    token = os.environ.get("GITHUB_TOKEN", "")
    headers = {"Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    articles = []
    for repo in repos:
        try:
            resp = requests.get(
                f"https://api.github.com/repos/{repo}/releases",
                headers=headers,
                params={"per_page": 5},
                timeout=10,
            )
            if resp.status_code != 200:
                continue
            for rel in resp.json():
                published = datetime.fromisoformat(
                    rel["published_at"].replace("Z", "+00:00")
                )
                if published < cutoff:
                    continue
                tag = rel.get("tag_name", "")
                name = rel.get("name", tag)
                articles.append({
                    "title": f"[Release] {repo} {name}",
                    "url": rel.get("html_url", ""),
                    "source": f"github/{repo}",
                    "published": published.isoformat(),
                    "layer": "github",
                    "body_snippet": (rel.get("body") or "")[:200],
                })
        except Exception as e:
            print(f"[github] Error fetching {repo}: {e}", file=sys.stderr)
    return articles


# ── Web search layer (Brave) ───────────────────────────────────────────

def fetch_brave_search(queries: list[str], cutoff: datetime) -> list[dict]:
    import requests

    api_key = os.environ.get("BRAVE_API_KEY", "")
    if not api_key:
        return []

    articles = []
    for query in queries:
        try:
            resp = requests.get(
                "https://api.search.brave.com/res/v1/web/search",
                headers={"X-Subscription-Token": api_key, "Accept": "application/json"},
                params={"q": query, "count": 10, "freshness": "pd"},
                timeout=10,
            )
            if resp.status_code != 200:
                continue
            for result in resp.json().get("web", {}).get("results", []):
                articles.append({
                    "title": result.get("title", "Untitled"),
                    "url": result.get("url", ""),
                    "source": f"brave/{query[:30]}",
                    "published": datetime.now(timezone.utc).isoformat(),
                    "layer": "search",
                    "snippet": result.get("description", ""),
                })
        except Exception as e:
            print(f"[search] Error searching '{query}': {e}", file=sys.stderr)
    return articles


# ── Dedup + scoring ─────────────────────────────────────────────────────

def tokenize(text: str) -> set[str]:
    return set(re.sub(r"[^\w\s]", "", text.lower()).split())


def jaccard(a: set, b: set) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def dedup_and_score(articles: list[dict]) -> list[dict]:
    """Deduplicate by title similarity and score articles."""
    seen_titles: list[set[str]] = []
    unique: list[dict] = []

    for art in articles:
        tokens = tokenize(art["title"])
        is_dup = False
        for i, prev_tokens in enumerate(seen_titles):
            if jaccard(tokens, prev_tokens) > 0.6:
                unique[i]["score"] = unique[i].get("score", 0) + 5  # multi-source bonus
                is_dup = True
                break
        if not is_dup:
            seen_titles.append(tokens)
            score = 0
            url = art.get("url", "")
            for domain in PRIORITY_DOMAINS:
                if domain in url:
                    score += 3
                    break
            try:
                pub = datetime.fromisoformat(art["published"])
                age_hours = (datetime.now(timezone.utc) - pub).total_seconds() / 3600
                if age_hours < 6:
                    score += 2
            except Exception:
                pass
            title_tokens = tokenize(art["title"])
            if title_tokens & RELEVANT_KEYWORDS:
                score += 1
            art["score"] = score
            unique.append(art)

    unique.sort(key=lambda a: a.get("score", 0), reverse=True)
    return unique


# ── Output formatters ───────────────────────────────────────────────────

def format_markdown(articles: list[dict], hours: int) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = [
        f"# Tech News Digest",
        f"",
        f"Generated: {now} | Window: {hours}h | Articles: {len(articles)}",
        f"",
        f"---",
        f"",
    ]
    for i, art in enumerate(articles, 1):
        score = art.get("score", 0)
        layer = art.get("layer", "?")
        source = art.get("source", "")
        pub = art.get("published", "")[:16]
        lines.append(f"### {i}. {art['title']}")
        lines.append(f"")
        lines.append(f"- **Source**: {source} ({layer})")
        lines.append(f"- **Published**: {pub}")
        lines.append(f"- **Score**: {score}")
        if art.get("url"):
            lines.append(f"- **Link**: {art['url']}")
        if art.get("body_snippet"):
            lines.append(f"- {art['body_snippet']}")
        if art.get("snippet"):
            lines.append(f"- {art['snippet']}")
        lines.append(f"")
    return "\n".join(lines)


def format_json(articles: list[dict]) -> str:
    return json.dumps(articles, indent=2, ensure_ascii=False)


# ── Main ────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Tech News Digest")
    parser.add_argument("--hours", type=int, default=24, help="Lookback window in hours (default: 24)")
    parser.add_argument("--max-items", type=int, default=30, help="Max articles to output (default: 30)")
    parser.add_argument("--sources", help="Path to custom sources JSON file")
    parser.add_argument("--output", choices=["markdown", "json"], default="markdown", help="Output format")
    args = parser.parse_args()

    cutoff = datetime.now(timezone.utc) - timedelta(hours=args.hours)
    sources = load_sources(args.sources)

    print(f"Fetching tech news (past {args.hours}h)...", file=sys.stderr)

    # Fetch from all layers
    all_articles = []

    rss_feeds = sources.get("rss", [])
    if rss_feeds:
        print(f"  [rss] {len(rss_feeds)} feeds...", file=sys.stderr)
        all_articles.extend(fetch_rss(rss_feeds, cutoff))

    github_repos = sources.get("github", [])
    if github_repos:
        print(f"  [github] {len(github_repos)} repos...", file=sys.stderr)
        all_articles.extend(fetch_github_releases(github_repos, cutoff))

    search_queries = sources.get("search_queries", [])
    if search_queries:
        print(f"  [search] {len(search_queries)} queries...", file=sys.stderr)
        all_articles.extend(fetch_brave_search(search_queries, cutoff))

    print(f"  Raw articles: {len(all_articles)}", file=sys.stderr)

    # Dedup and score
    scored = dedup_and_score(all_articles)[:args.max_items]
    print(f"  After dedup/score: {len(scored)}", file=sys.stderr)

    # Output
    if args.output == "json":
        print(format_json(scored))
    else:
        print(format_markdown(scored, args.hours))


if __name__ == "__main__":
    main()
