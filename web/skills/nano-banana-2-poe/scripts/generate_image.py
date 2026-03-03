#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "openai>=1.0.0",
#     "pillow>=10.0.0",
# ]
# ///
"""
Generate nano banana images using POE's Nano Banana 2 model via OpenAI-compatible API.

Usage:
    uv run generate_image.py --prompt "your image description" --filename "output.png" [--api-key KEY]
"""

import argparse
import os
import sys
from pathlib import Path


def get_api_key(provided_key: str | None) -> str | None:
    """Get API key from argument first, then environment."""
    if provided_key:
        return provided_key
    return os.environ.get("POE_API_KEY")


def main():
    parser = argparse.ArgumentParser(
        description="Generate images using POE's Nano Banana 2 model"
    )
    parser.add_argument(
        "--prompt", "-p",
        required=True,
        help="Image description/prompt"
    )
    parser.add_argument(
        "--filename", "-f",
        required=True,
        help="Output filename (e.g., nano-banana.png)"
    )
    parser.add_argument(
        "--api-key", "-k",
        help="POE API key (overrides POE_API_KEY env var)"
    )

    args = parser.parse_args()

    # Get API key
    api_key = get_api_key(args.api_key)
    if not api_key:
        print("Error: No API key provided.", file=sys.stderr)
        print("Please either:", file=sys.stderr)
        print("  1. Provide --api-key argument", file=sys.stderr)
        print("  2. Set POE_API_KEY environment variable", file=sys.stderr)
        sys.exit(1)

    # Import here after checking API key to avoid slow import on error
    from openai import OpenAI
    from PIL import Image as PILImage
    from io import BytesIO
    import re
    import urllib.request

    # Initialize client with POE's OpenAI-compatible API
    client = OpenAI(
        api_key=api_key,
        base_url="https://api.poe.com/v1"
    )

    # Set up output path
    output_path = Path(args.filename)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Generating image with prompt: {args.prompt}")

    try:
        # Call POE's Nano Banana 2 model
        response = client.chat.completions.create(
            model="nano-banana-2",
            messages=[{
                "role": "user",
                "content": args.prompt
            }]
        )

        content = response.choices[0].message.content

        # POE nano-banana-2 returns text with embedded image URLs.
        # Extract from markdown image syntax: ![alt](url)
        # or bare https://pfst.cf2.poecdn.net/... URLs on their own line.
        img_url = None

        # Try markdown image syntax first
        md_match = re.search(r'!\[.*?\]\((https://[^\s)]+)\)', content)
        if md_match:
            img_url = md_match.group(1)
        else:
            # Try bare URL (poecdn or any https image URL)
            url_match = re.search(
                r'(https://[^\s)]+\.(?:png|jpe?g|gif|webp|bmp)(?:\?[^\s)]*)?)',
                content,
            )
            if url_match:
                img_url = url_match.group(1)
            else:
                # Last resort: any poecdn URL
                cdn_match = re.search(r'(https://pfst\.cf2\.poecdn\.net/[^\s)]+)', content)
                if cdn_match:
                    img_url = cdn_match.group(1)

        if not img_url:
            print("Model response (no image URL found):", file=sys.stderr)
            print(content[:500], file=sys.stderr)
            print("\nError: No image URL found in response.", file=sys.stderr)
            sys.exit(1)

        print(f"Downloading image from: {img_url}")

        # Download and save as PNG
        req = urllib.request.Request(img_url, headers={"User-Agent": "nano-banana-2-poe/1.0"})
        with urllib.request.urlopen(req) as resp:
            image_data = resp.read()

        image = PILImage.open(BytesIO(image_data))
        if image.mode == 'RGBA':
            rgb_image = PILImage.new('RGB', image.size, (255, 255, 255))
            rgb_image.paste(image, mask=image.split()[3])
            rgb_image.save(str(output_path), 'PNG')
        elif image.mode == 'RGB':
            image.save(str(output_path), 'PNG')
        else:
            image.convert('RGB').save(str(output_path), 'PNG')

        full_path = output_path.resolve()
        print(f"\nImage saved: {full_path}")
        # OpenClaw parses MEDIA tokens and will attach the file on supported providers.
        print(f"MEDIA: {full_path}")

    except Exception as e:
        print(f"Error generating image: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
