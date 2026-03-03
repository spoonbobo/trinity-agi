#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
#     "youtube-transcript-api>=1.0.0",
# ]
# ///
"""
YouTube Digest: fetch latest videos from channels, extract transcripts, produce a digest.

Usage:
    uv run digest.py --channels "@Fireship,@lexfridman" --hours 48
    uv run digest.py --channels "@TED" --hours 48 --transcript --max-videos 10
    uv run digest.py --search "OpenClaw,AI agents" --hours 72 --transcript
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path


def get_api_key(provided: str | None) -> str | None:
    if provided:
        return provided
    return os.environ.get("YOUTUBE_API_KEY")


# ── Channel resolution ──────────────────────────────────────────────────

def resolve_channel_id(handle: str, api_key: str) -> str | None:
    """Resolve a @handle or channel name to a channel ID via YouTube Data API v3."""
    import requests

    handle = handle.strip()
    # Already a channel ID
    if handle.startswith("UC") and len(handle) == 24:
        return handle

    # Strip @ prefix for forHandle param
    clean = handle.lstrip("@")

    # Try forHandle (works for @handles)
    resp = requests.get(
        "https://www.googleapis.com/youtube/v3/channels",
        params={"part": "id,contentDetails", "forHandle": clean, "key": api_key},
        timeout=10,
    )
    if resp.status_code == 200:
        items = resp.json().get("items", [])
        if items:
            return items[0]["id"]

    # Fallback: search for the channel
    resp = requests.get(
        "https://www.googleapis.com/youtube/v3/search",
        params={"part": "snippet", "q": handle, "type": "channel", "maxResults": 1, "key": api_key},
        timeout=10,
    )
    if resp.status_code == 200:
        items = resp.json().get("items", [])
        if items:
            return items[0]["snippet"]["channelId"]

    return None


def get_uploads_playlist(channel_id: str, api_key: str) -> str | None:
    """Get the uploads playlist ID for a channel."""
    import requests

    resp = requests.get(
        "https://www.googleapis.com/youtube/v3/channels",
        params={"part": "contentDetails", "id": channel_id, "key": api_key},
        timeout=10,
    )
    if resp.status_code == 200:
        items = resp.json().get("items", [])
        if items:
            return items[0]["contentDetails"]["relatedPlaylists"]["uploads"]
    return None


def fetch_recent_uploads(playlist_id: str, api_key: str, cutoff: datetime, max_results: int = 20) -> list[dict]:
    """Fetch recent videos from an uploads playlist."""
    import requests

    videos = []
    resp = requests.get(
        "https://www.googleapis.com/youtube/v3/playlistItems",
        params={
            "part": "snippet",
            "playlistId": playlist_id,
            "maxResults": min(max_results, 50),
            "key": api_key,
        },
        timeout=10,
    )
    if resp.status_code != 200:
        return videos

    for item in resp.json().get("items", []):
        snippet = item["snippet"]
        published = datetime.fromisoformat(
            snippet["publishedAt"].replace("Z", "+00:00")
        )
        if published < cutoff:
            continue
        videos.append({
            "video_id": snippet["resourceId"]["videoId"],
            "title": snippet["title"],
            "channel": snippet.get("channelTitle", ""),
            "published": published.isoformat(),
            "url": f"https://www.youtube.com/watch?v={snippet['resourceId']['videoId']}",
            "thumbnail": snippet.get("thumbnails", {}).get("medium", {}).get("url", ""),
        })
    return videos


# ── Search mode ─────────────────────────────────────────────────────────

def search_videos(query: str, api_key: str, cutoff: datetime, max_results: int = 10) -> list[dict]:
    """Search YouTube for recent videos matching a query."""
    import requests

    videos = []
    resp = requests.get(
        "https://www.googleapis.com/youtube/v3/search",
        params={
            "part": "snippet",
            "q": query,
            "type": "video",
            "order": "date",
            "publishedAfter": cutoff.isoformat(),
            "maxResults": min(max_results, 50),
            "key": api_key,
        },
        timeout=10,
    )
    if resp.status_code != 200:
        print(f"[search] Error ({resp.status_code}): {resp.text[:200]}", file=sys.stderr)
        return videos

    for item in resp.json().get("items", []):
        snippet = item["snippet"]
        vid = item["id"]["videoId"]
        published = datetime.fromisoformat(
            snippet["publishedAt"].replace("Z", "+00:00")
        )
        videos.append({
            "video_id": vid,
            "title": snippet["title"],
            "channel": snippet.get("channelTitle", ""),
            "published": published.isoformat(),
            "url": f"https://www.youtube.com/watch?v={vid}",
            "thumbnail": snippet.get("thumbnails", {}).get("medium", {}).get("url", ""),
        })
    return videos


# ── Transcript extraction ───────────────────────────────────────────────

def fetch_transcript(video_id: str) -> str | None:
    """Fetch transcript using youtube-transcript-api (free, no key needed)."""
    try:
        from youtube_transcript_api import YouTubeTranscriptApi

        transcript_list = YouTubeTranscriptApi.get_transcript(video_id, languages=["en", "zh-Hans", "zh-Hant", "ja"])
        text = " ".join(seg["text"] for seg in transcript_list)
        return text
    except Exception:
        # Try without language filter
        try:
            transcript_list = YouTubeTranscriptApi.get_transcript(video_id)
            text = " ".join(seg["text"] for seg in transcript_list)
            return text
        except Exception as e:
            print(f"[transcript] Could not get transcript for {video_id}: {e}", file=sys.stderr)
            return None


def summarize_transcript(text: str, max_chars: int = 500) -> str:
    """Simple extractive summary: pick key sentences from transcript."""
    sentences = [s.strip() for s in text.replace("\n", " ").split(".") if len(s.strip()) > 20]
    if not sentences:
        return text[:max_chars]

    # Pick first, middle, and spaced sentences
    picks = []
    step = max(1, len(sentences) // 5)
    for i in range(0, len(sentences), step):
        picks.append(sentences[i])
        if len(". ".join(picks)) > max_chars:
            break

    return ". ".join(picks[:5]) + "."


# ── Seen-video tracking ────────────────────────────────────────────────

def load_seen(path: str | None) -> set[str]:
    if not path:
        return set()
    p = Path(path)
    if p.exists():
        return set(p.read_text().strip().splitlines())
    return set()


def save_seen(path: str | None, seen: set[str]):
    if not path:
        return
    Path(path).write_text("\n".join(sorted(seen)) + "\n")


# ── Output formatters ───────────────────────────────────────────────────

def format_markdown(videos: list[dict], hours: int) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = [
        f"# YouTube Digest",
        f"",
        f"Generated: {now} | Window: {hours}h | Videos: {len(videos)}",
        f"",
        f"---",
        f"",
    ]
    for i, vid in enumerate(videos, 1):
        pub = vid.get("published", "")[:16]
        lines.append(f"### {i}. {vid['title']}")
        lines.append(f"")
        lines.append(f"- **Channel**: {vid['channel']}")
        lines.append(f"- **Published**: {pub}")
        lines.append(f"- **Link**: {vid['url']}")
        if vid.get("summary"):
            lines.append(f"- **Key insights**:")
            for bullet in vid["summary"].split(". "):
                bullet = bullet.strip()
                if bullet:
                    lines.append(f"  - {bullet}")
        lines.append(f"")
    return "\n".join(lines)


def format_json(videos: list[dict]) -> str:
    return json.dumps(videos, indent=2, ensure_ascii=False)


# ── Main ────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="YouTube Digest")
    parser.add_argument("--channels", help="Comma-separated channel handles (e.g. @Fireship,@lexfridman)")
    parser.add_argument("--search", help="Comma-separated search queries (e.g. 'OpenClaw,AI agents')")
    parser.add_argument("--hours", type=int, default=48, help="Lookback window in hours (default: 48)")
    parser.add_argument("--max-videos", type=int, default=10, help="Max videos to process (default: 10)")
    parser.add_argument("--transcript", action="store_true", help="Fetch and summarize transcripts")
    parser.add_argument("--seen-file", help="Path to seen-videos tracking file")
    parser.add_argument("--output", choices=["markdown", "json"], default="markdown", help="Output format")
    parser.add_argument("--api-key", help="YouTube Data API v3 key (overrides YOUTUBE_API_KEY env var)")
    args = parser.parse_args()

    if not args.channels and not args.search:
        print("Error: provide --channels or --search", file=sys.stderr)
        sys.exit(1)

    api_key = get_api_key(args.api_key)
    if not api_key:
        print("Error: No YouTube API key provided.", file=sys.stderr)
        print("Please either:", file=sys.stderr)
        print("  1. Provide --api-key argument", file=sys.stderr)
        print("  2. Set YOUTUBE_API_KEY environment variable", file=sys.stderr)
        sys.exit(1)

    cutoff = datetime.now(timezone.utc) - timedelta(hours=args.hours)
    seen = load_seen(args.seen_file)
    all_videos: list[dict] = []

    # Channel mode
    if args.channels:
        channels = [c.strip() for c in args.channels.split(",") if c.strip()]
        print(f"Fetching videos from {len(channels)} channels (past {args.hours}h)...", file=sys.stderr)

        for handle in channels:
            print(f"  Resolving {handle}...", file=sys.stderr)
            channel_id = resolve_channel_id(handle, api_key)
            if not channel_id:
                print(f"  [warn] Could not resolve {handle}", file=sys.stderr)
                continue

            playlist_id = get_uploads_playlist(channel_id, api_key)
            if not playlist_id:
                print(f"  [warn] No uploads playlist for {handle}", file=sys.stderr)
                continue

            videos = fetch_recent_uploads(playlist_id, api_key, cutoff, args.max_videos)
            print(f"  {handle}: {len(videos)} recent videos", file=sys.stderr)
            all_videos.extend(videos)

    # Search mode
    if args.search:
        queries = [q.strip() for q in args.search.split(",") if q.strip()]
        print(f"Searching {len(queries)} queries (past {args.hours}h)...", file=sys.stderr)

        for query in queries:
            videos = search_videos(query, api_key, cutoff, args.max_videos)
            print(f"  '{query}': {len(videos)} results", file=sys.stderr)
            all_videos.extend(videos)

    # Filter out seen videos
    if seen:
        before = len(all_videos)
        all_videos = [v for v in all_videos if v["video_id"] not in seen]
        print(f"  Filtered {before - len(all_videos)} already-seen videos", file=sys.stderr)

    # Dedup by video_id
    seen_ids: set[str] = set()
    unique: list[dict] = []
    for v in all_videos:
        if v["video_id"] not in seen_ids:
            seen_ids.add(v["video_id"])
            unique.append(v)
    all_videos = unique[:args.max_videos]

    # Fetch transcripts if requested
    if args.transcript and all_videos:
        print(f"  Fetching transcripts for {len(all_videos)} videos...", file=sys.stderr)
        for vid in all_videos:
            transcript = fetch_transcript(vid["video_id"])
            if transcript:
                vid["summary"] = summarize_transcript(transcript)
                vid["transcript_length"] = len(transcript)
            else:
                vid["summary"] = "(transcript unavailable)"

    # Update seen file
    if args.seen_file:
        for v in all_videos:
            seen.add(v["video_id"])
        save_seen(args.seen_file, seen)

    print(f"  Total videos: {len(all_videos)}", file=sys.stderr)

    # Output
    if args.output == "json":
        print(format_json(all_videos))
    else:
        print(format_markdown(all_videos, args.hours))


if __name__ == "__main__":
    main()
