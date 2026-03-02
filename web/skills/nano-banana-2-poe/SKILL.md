---
name: nano-banana-2-poe
description: Generate a nano banana image via POE's Nano Banana 2 model.
homepage: https://poe.com/nano-banana-2
metadata:
  {
    "openclaw":
      {
        "emoji": "🍌",
        "requires": { "bins": ["uv"], "env": ["POE_API_KEY"] },
        "primaryEnv": "POE_API_KEY",
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

# Nano Banana 2 (POE)

Use the bundled script to generate a nano banana image via POE's API.

Generate

```bash
uv run {baseDir}/scripts/generate_image.py --prompt "a cute nano banana" --filename "nano-banana.png"
```

API key

- `POE_API_KEY` env var
- Or set `skills."nano-banana-2-poe".apiKey` / `skills."nano-banana-2-poe".env.POE_API_KEY` in `~/.openclaw/openclaw.json`

Notes

- Uses model `nano-banana-2` via POE's OpenAI-compatible API (https://api.poe.com/v1).
- Use timestamps in filenames: `yyyy-mm-dd-hh-mm-ss-name.png`.
- The script prints a `MEDIA:` line for OpenClaw to auto-attach on supported chat providers.
- Do not read the image back; report the saved path only.
