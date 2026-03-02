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
    import base64

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

        # Extract image URL from response
        content = response.choices[0].message.content
        
        # Check if content is a URL or base64 image
        if content.startswith("http"):
            # Download image from URL
            import urllib.request
            urllib.request.urlretrieve(content, str(output_path))
        elif content.startswith("data:image"):
            # Extract base64 data
            base64_data = content.split(",")[1]
            image_data = base64.b64decode(base64_data)
            image = PILImage.open(BytesIO(image_data))
            image.save(str(output_path), 'PNG')
        else:
            # Try to parse as base64 directly
            try:
                image_data = base64.b64decode(content)
                image = PILImage.open(BytesIO(image_data))
                image.save(str(output_path), 'PNG')
            except Exception:
                print(f"Error: Unable to parse response content: {content[:100]}", file=sys.stderr)
                sys.exit(1)

        full_path = output_path.resolve()
        print(f"\nImage saved: {full_path}")
        # OpenClaw parses MEDIA tokens and will attach the file on supported providers.
        print(f"MEDIA: {full_path}")

    except Exception as e:
        print(f"Error generating image: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
