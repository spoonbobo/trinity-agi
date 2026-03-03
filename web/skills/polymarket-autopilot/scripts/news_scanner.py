#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Scan news headlines and cross-reference with open Polymarket markets.

Fetches headlines from free RSS/Atom feeds (no API key required), extracts
keywords, and matches them against active Polymarket markets to find
news-driven trading opportunities.

Usage:
    uv run news_scanner.py [--limit 30] [--min-relevance 2] [--json]
    uv run news_scanner.py --feeds "https://feeds.bbci.co.uk/news/rss.xml,https://rss.nytimes.com/services/xml/rss/nyt/World.xml"
"""

import argparse
import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

import requests

GAMMA_API = "https://gamma-api.polymarket.com"

# Default RSS feeds (no API key required)
DEFAULT_FEEDS = [
    "https://feeds.bbci.co.uk/news/rss.xml",
    "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml",
    "https://feeds.reuters.com/reuters/topNews",
    "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en",
]

# Common stop words to exclude from keyword matching
STOP_WORDS = {
    "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "can", "shall", "to", "of", "in", "for",
    "on", "with", "at", "by", "from", "as", "into", "about", "after",
    "before", "between", "under", "over", "through", "during", "up",
    "down", "out", "off", "again", "then", "than", "too", "very", "just",
    "but", "and", "or", "nor", "not", "no", "so", "if", "when", "that",
    "this", "these", "those", "it", "its", "he", "she", "they", "we",
    "you", "my", "your", "his", "her", "our", "their", "what", "which",
    "who", "whom", "how", "why", "where", "each", "every", "all", "any",
    "both", "few", "more", "most", "some", "such", "only", "own", "same",
    "new", "says", "said", "also", "one", "two", "first", "last", "many",
    "much", "well", "back", "even", "still", "way", "take", "come", "make",
    "like", "get", "go", "see", "know", "think", "look", "want", "give",
    "use", "find", "tell", "ask", "work", "seem", "feel", "try", "leave",
    "call", "need", "become", "keep", "let", "begin", "show", "hear",
    "play", "run", "move", "live", "believe", "bring", "happen", "must",
    "report", "reports", "according", "people", "time", "year", "years",
    "day", "days", "week", "month", "today", "now", "us", "world", "news",
}


def fetch_rss(url: str) -> list[dict]:
    """Fetch and parse an RSS/Atom feed. Returns list of {title, link, summary, published}."""
    headers = {"User-Agent": "news-scanner/1.0 (openclaw skill)"}
    try:
        resp = requests.get(url, headers=headers, timeout=10)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  Warning: Failed to fetch {url}: {e}", file=sys.stderr)
        return []

    items = []
    try:
        root = ET.fromstring(resp.content)

        # RSS 2.0 format
        for item in root.iter("item"):
            title = (item.findtext("title") or "").strip()
            link = (item.findtext("link") or "").strip()
            desc = (item.findtext("description") or "").strip()
            pub = (item.findtext("pubDate") or "").strip()

            if title:
                # Strip HTML from description
                desc_clean = re.sub(r"<[^>]+>", "", desc)[:200]
                items.append({
                    "title": title,
                    "link": link,
                    "summary": desc_clean,
                    "published": pub,
                    "source": url,
                })

        # Atom format fallback
        if not items:
            ns = {"atom": "http://www.w3.org/2005/Atom"}
            for entry in root.findall(".//atom:entry", ns):
                title = (entry.findtext("atom:title", namespaces=ns) or "").strip()
                link_el = entry.find("atom:link", ns)
                link = link_el.get("href", "") if link_el is not None else ""
                summary = (entry.findtext("atom:summary", namespaces=ns) or "").strip()
                pub = (entry.findtext("atom:published", namespaces=ns) or "").strip()

                if title:
                    summary_clean = re.sub(r"<[^>]+>", "", summary)[:200]
                    items.append({
                        "title": title,
                        "link": link,
                        "summary": summary_clean,
                        "published": pub,
                        "source": url,
                    })

    except ET.ParseError as e:
        print(f"  Warning: XML parse error for {url}: {e}", file=sys.stderr)

    return items


def extract_keywords(text: str) -> set[str]:
    """Extract meaningful keywords from text (lowercase, no stop words)."""
    words = re.findall(r"[a-zA-Z]{3,}", text.lower())
    return {w for w in words if w not in STOP_WORDS and len(w) >= 3}


def fetch_active_markets(limit: int = 200) -> list[dict]:
    """Fetch active markets from the Gamma API."""
    markets = []
    offset = 0
    page_size = min(limit, 100)

    while len(markets) < limit:
        try:
            resp = requests.get(
                f"{GAMMA_API}/markets",
                params={"active": "true", "closed": "false", "limit": page_size, "offset": offset},
                timeout=15,
            )
            resp.raise_for_status()
            batch = resp.json()
        except requests.RequestException as e:
            print(f"  Error fetching markets: {e}", file=sys.stderr)
            break

        if not batch:
            break
        markets.extend(batch)
        offset += page_size
        if len(batch) < page_size:
            break
        time.sleep(0.3)

    return markets[:limit]


def match_news_to_markets(
    headlines: list[dict],
    markets: list[dict],
    min_relevance: int = 2,
) -> list[dict]:
    """Cross-reference headlines with markets by keyword overlap."""

    # Pre-compute market keywords
    market_data = []
    for m in markets:
        question = m.get("question", "")
        description = m.get("description", "") or ""
        tags = " ".join(parse_json_field(m.get("tags")))
        combined = f"{question} {description} {tags}"
        keywords = extract_keywords(combined)

        token_ids = parse_json_field(m.get("clobTokenIds"))
        outcomes = parse_json_field(m.get("outcomes")) or ["Yes", "No"]

        market_data.append({
            "question": question,
            "keywords": keywords,
            "slug": m.get("slug", ""),
            "volume": float(m.get("volume", 0) or 0),
            "token_ids": token_ids,
            "outcomes": outcomes,
            "condition_id": m.get("conditionId", m.get("condition_id", "")),
        })

    matches = []
    seen = set()

    for headline in headlines:
        h_text = f"{headline['title']} {headline.get('summary', '')}"
        h_keywords = extract_keywords(h_text)

        for md in market_data:
            overlap = h_keywords & md["keywords"]
            relevance = len(overlap)

            if relevance >= min_relevance:
                key = (headline["title"][:50], md["question"][:50])
                if key in seen:
                    continue
                seen.add(key)

                matches.append({
                    "headline": headline["title"],
                    "headline_link": headline.get("link", ""),
                    "headline_summary": headline.get("summary", ""),
                    "market_question": md["question"],
                    "market_slug": md["slug"],
                    "market_volume": md["volume"],
                    "token_ids": md["token_ids"],
                    "matching_keywords": sorted(overlap),
                    "relevance_score": relevance,
                })

    # Sort by relevance descending, then by volume
    matches.sort(key=lambda x: (x["relevance_score"], x["market_volume"]), reverse=True)
    return matches


def parse_json_field(raw) -> list:
    """Parse a JSON string or return as-is if already a list."""
    if isinstance(raw, list):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                return parsed
        except (json.JSONDecodeError, TypeError):
            pass
    return []


def main():
    parser = argparse.ArgumentParser(description="News-to-Polymarket opportunity scanner")
    parser.add_argument("--limit", "-l", type=int, default=50, help="Max markets to scan (default: 50)")
    parser.add_argument("--min-relevance", type=int, default=2, help="Min keyword overlap to count as a match (default: 2)")
    parser.add_argument(
        "--feeds",
        help="Comma-separated RSS feed URLs (default: BBC, NYT, Reuters, Google News)",
    )
    parser.add_argument("--json", action="store_true", dest="output_json", help="Output JSON")

    args = parser.parse_args()

    feeds = DEFAULT_FEEDS
    if args.feeds:
        feeds = [f.strip() for f in args.feeds.split(",") if f.strip()]

    # Fetch news
    print(f"Fetching headlines from {len(feeds)} feed(s)...", file=sys.stderr)
    all_headlines: list[dict] = []
    for feed_url in feeds:
        items = fetch_rss(feed_url)
        all_headlines.extend(items)
        time.sleep(0.5)

    print(f"Collected {len(all_headlines)} headlines.", file=sys.stderr)

    if not all_headlines:
        print("No headlines fetched. Check feed URLs.", file=sys.stderr)
        sys.exit(1)

    # Fetch markets
    print(f"Fetching up to {args.limit} active Polymarket markets...", file=sys.stderr)
    markets = fetch_active_markets(args.limit)
    print(f"Fetched {len(markets)} markets. Matching...", file=sys.stderr)

    # Match
    matches = match_news_to_markets(all_headlines, markets, min_relevance=args.min_relevance)

    if args.output_json:
        print(json.dumps(matches, indent=2))
    else:
        if not matches:
            print(f"\nNo news-market matches found (min relevance: {args.min_relevance} keywords).")
            print("Try lowering --min-relevance or adding more feeds.")
        else:
            print(f"\n{'='*70}")
            print(f"  NEWS-MARKET MATCHES -- {len(matches)} found")
            print(f"  {len(all_headlines)} headlines x {len(markets)} markets")
            print(f"{'='*70}")

            for i, m in enumerate(matches[:20], 1):
                print(f"\n  {i}. [{m['relevance_score']} keywords] {m['headline'][:65]}")
                print(f"     Market: {m['market_question'][:60]}")
                print(f"     Keywords: {', '.join(m['matching_keywords'][:8])}")
                print(f"     Volume: ${m['market_volume']:,.0f}  |  Slug: {m['market_slug']}")
                if m["headline_link"]:
                    print(f"     News: {m['headline_link'][:70]}")

            if len(matches) > 20:
                print(f"\n  ... and {len(matches) - 20} more matches (use --json for full output)")

        print()

    print(f"Scan complete. {len(matches)} matches from {len(all_headlines)} headlines.", file=sys.stderr)


if __name__ == "__main__":
    main()
