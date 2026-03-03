---
name: youtube-digest
description: Fetch latest videos from YouTube channels, extract transcripts, and generate a digest with key insights. Use when asked for YouTube digest, channel updates, or video summaries.
homepage: https://github.com/hesamsheikh/awesome-openclaw-usecases
metadata:
  {
    "openclaw":
      {
        "emoji": "📺",
        "requires": { "bins": ["uv"] },
        "primaryEnv": "YOUTUBE_API_KEY",
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

# YouTube Digest

Fetch latest videos from YouTube channels, extract transcripts, and produce a digest.

## Generate a channel digest

```bash
uv run {baseDir}/scripts/digest.py --channels "@Fireship,@lexfridman,@ThePrimeTimeagen" --hours 48
```

With transcripts and summaries:

```bash
uv run {baseDir}/scripts/digest.py --channels "@TED,@Fireship" --hours 48 --transcript --max-videos 10
```

Keyword search mode:

```bash
uv run {baseDir}/scripts/digest.py --search "OpenClaw,AI agents" --hours 72 --transcript
```

JSON output:

```bash
uv run {baseDir}/scripts/digest.py --channels "@Fireship" --output json
```

## Features

- Resolves `@handle` to channel ID via YouTube Data API v3
- Fetches recent uploads via channel uploads playlist
- Extracts transcripts via `youtube-transcript-api` (free, no API key, no binary)
- Tracks seen videos in `--seen-file` to avoid reprocessing
- Outputs markdown with title, channel, link, date, and transcript bullets

## Seen-video tracking

```bash
uv run {baseDir}/scripts/digest.py --channels "@Fireship" --seen-file seen-videos.txt
```

Only new (unseen) videos are processed. After processing, video IDs are appended to the file.

## Cron

```text
Every morning at 8am, fetch latest videos from @TED, @Fireship, @lexfridman and give me a digest with key insights.
Save my channel list to memory so I can add/remove channels later.
```

## API keys

- `YOUTUBE_API_KEY` — YouTube Data API v3 key (required for channel resolution and upload listing; get one at https://console.cloud.google.com/)

## Notes

- Transcript extraction is free (no API key, no credits) via `youtube-transcript-api`.
- `channel/latest` listing requires `YOUTUBE_API_KEY`.
- Use timestamps in filenames: `yyyy-mm-dd-yt-digest.md`.
