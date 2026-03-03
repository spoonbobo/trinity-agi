#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Fetch and format a digest of top posts from Reddit subreddits.

Uses Reddit's public JSON API (no authentication or API key required).

Usage:
    uv run fetch_reddit.py --subreddits "python,machinelearning,selfhosted"
    uv run fetch_reddit.py -s "worldnews" --sort top --time day --limit 15
    uv run fetch_reddit.py -s "LocalLLaMA,singularity" --min-score 100 --include-comments
    uv run fetch_reddit.py -s "homelab" --json
"""

import argparse
import json
import sys
import time
from datetime import datetime, timezone

import requests

USER_AGENT = "reddit-digest/1.0 (openclaw skill; +https://github.com/trinityagi/trinity-agi)"
BASE_URL = "https://www.reddit.com"


def fetch_subreddit(
    subreddit: str,
    sort: str = "hot",
    time_filter: str = "day",
    limit: int = 10,
    min_score: int = 0,
) -> list[dict]:
    """Fetch posts from a subreddit via Reddit's public JSON API."""
    url = f"{BASE_URL}/r/{subreddit}/{sort}.json"
    params: dict = {"limit": min(limit * 2, 100), "raw_json": 1}
    if sort == "top":
        params["t"] = time_filter

    headers = {"User-Agent": USER_AGENT}

    try:
        resp = requests.get(url, params=params, headers=headers, timeout=15)
        if resp.status_code == 429:
            print(f"  Rate limited on r/{subreddit}, waiting 5s...", file=sys.stderr)
            time.sleep(5)
            resp = requests.get(url, params=params, headers=headers, timeout=15)
        resp.raise_for_status()
        data = resp.json()
    except requests.RequestException as e:
        print(f"Error fetching r/{subreddit}: {e}", file=sys.stderr)
        return []

    posts = []
    children = data.get("data", {}).get("children", [])

    for child in children:
        if child.get("kind") != "t3":
            continue
        p = child["data"]

        # Skip stickied/pinned posts
        if p.get("stickied", False):
            continue

        score = p.get("score", 0)
        if score < min_score:
            continue

        # Trim selftext preview
        selftext = p.get("selftext", "") or ""
        if len(selftext) > 300:
            selftext = selftext[:297] + "..."

        created_utc = p.get("created_utc", 0)
        created_str = ""
        if created_utc:
            created_str = datetime.fromtimestamp(created_utc, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

        post = {
            "subreddit": subreddit,
            "title": p.get("title", ""),
            "score": score,
            "num_comments": p.get("num_comments", 0),
            "author": p.get("author", "[deleted]"),
            "url": p.get("url", ""),
            "permalink": f"https://www.reddit.com{p.get('permalink', '')}",
            "selftext_preview": selftext,
            "created": created_str,
            "is_self": p.get("is_self", False),
            "link_flair_text": p.get("link_flair_text", ""),
            "id": p.get("id", ""),
        }
        posts.append(post)

        if len(posts) >= limit:
            break

    return posts


def fetch_top_comments(post_id: str, subreddit: str, limit: int = 3) -> list[dict]:
    """Fetch top comments for a post."""
    url = f"{BASE_URL}/r/{subreddit}/comments/{post_id}.json"
    params = {"limit": limit, "sort": "top", "raw_json": 1}
    headers = {"User-Agent": USER_AGENT}

    try:
        resp = requests.get(url, params=params, headers=headers, timeout=10)
        resp.raise_for_status()
        data = resp.json()
    except requests.RequestException:
        return []

    comments = []
    if len(data) < 2:
        return []

    children = data[1].get("data", {}).get("children", [])
    for child in children[:limit]:
        if child.get("kind") != "t1":
            continue
        c = child["data"]
        body = c.get("body", "") or ""
        if len(body) > 200:
            body = body[:197] + "..."

        comments.append({
            "author": c.get("author", "[deleted]"),
            "score": c.get("score", 0),
            "body": body,
        })

    return comments


def print_digest(
    all_posts: dict[str, list[dict]],
    include_comments: bool = False,
) -> None:
    """Print a human-readable digest grouped by subreddit."""
    total_posts = sum(len(posts) for posts in all_posts.values())

    if total_posts == 0:
        print("No posts found matching criteria.")
        return

    print(f"\n{'='*70}")
    print(f"  REDDIT DIGEST -- {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}")
    print(f"  {total_posts} posts across {len(all_posts)} subreddit(s)")
    print(f"{'='*70}")

    for sub, posts in all_posts.items():
        if not posts:
            continue

        print(f"\n  r/{sub}  ({len(posts)} posts)")
        print(f"  {'-'*60}")

        for i, p in enumerate(posts, 1):
            flair = f" [{p['link_flair_text']}]" if p["link_flair_text"] else ""
            print(f"\n  {i}. {p['title']}{flair}")
            print(f"     {p['score']:>5} pts  |  {p['num_comments']} comments  |  u/{p['author']}  |  {p['created']}")

            if p["selftext_preview"]:
                print(f"     {p['selftext_preview'][:120]}")

            if not p["is_self"]:
                print(f"     Link: {p['url']}")

            print(f"     {p['permalink']}")

            if include_comments and p.get("comments"):
                for c in p["comments"]:
                    print(f"       > u/{c['author']} ({c['score']} pts): {c['body'][:100]}")

    print()


def main():
    parser = argparse.ArgumentParser(description="Reddit digest fetcher")
    parser.add_argument(
        "--subreddits", "-s",
        required=True,
        help="Comma-separated list of subreddits (e.g. 'python,machinelearning,selfhosted')",
    )
    parser.add_argument(
        "--sort",
        choices=["hot", "top", "new", "rising"],
        default="hot",
        help="Sort order (default: hot)",
    )
    parser.add_argument(
        "--time", "-t",
        choices=["hour", "day", "week", "month", "year", "all"],
        default="day",
        dest="time_filter",
        help="Time window for 'top' sort (default: day)",
    )
    parser.add_argument(
        "--limit", "-l",
        type=int,
        default=10,
        help="Posts per subreddit (default: 10)",
    )
    parser.add_argument(
        "--min-score",
        type=int,
        default=0,
        help="Minimum upvotes to include (default: 0)",
    )
    parser.add_argument(
        "--include-comments", "-c",
        action="store_true",
        help="Fetch top 3 comments per post",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="output_json",
        help="Output raw JSON instead of formatted digest",
    )

    args = parser.parse_args()

    subreddits = [s.strip() for s in args.subreddits.split(",") if s.strip()]
    if not subreddits:
        print("Error: No subreddits provided.", file=sys.stderr)
        sys.exit(1)

    all_posts: dict[str, list[dict]] = {}

    for sub in subreddits:
        print(f"Fetching r/{sub} ({args.sort})...", file=sys.stderr)
        posts = fetch_subreddit(
            subreddit=sub,
            sort=args.sort,
            time_filter=args.time_filter,
            limit=args.limit,
            min_score=args.min_score,
        )

        if args.include_comments and posts:
            for p in posts:
                time.sleep(0.5)  # rate limit
                p["comments"] = fetch_top_comments(p["id"], sub)

        all_posts[sub] = posts
        # Be polite: ~1 request/second
        time.sleep(1.0)

    if args.output_json:
        print(json.dumps(all_posts, indent=2, default=str))
    else:
        print_digest(all_posts, include_comments=args.include_comments)

    total = sum(len(p) for p in all_posts.values())
    print(f"Done. {total} posts fetched from {len(subreddits)} subreddit(s).", file=sys.stderr)


if __name__ == "__main__":
    main()
