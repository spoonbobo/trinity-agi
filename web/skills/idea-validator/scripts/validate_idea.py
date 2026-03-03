#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Validate a project idea by scanning GitHub, npm, and PyPI for existing competitors.
Returns a reality_signal score (0-100) indicating how crowded the space is.

Usage:
    uv run validate_idea.py --query "AI code review tool"
    uv run validate_idea.py --query "MCP server for idea validation" --depth quick
"""

import argparse
import json
import math
import os
import sys
import time
from urllib.parse import quote_plus

import requests

# Rate limit tracking
_last_github_request = 0.0


def _github_headers() -> dict:
    """Build GitHub API headers, using GITHUB_TOKEN if available."""
    headers = {"Accept": "application/vnd.github.v3+json", "User-Agent": "idea-validator/1.0"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"token {token}"
    return headers


def _rate_limited_get(url: str, headers: dict, params: dict | None = None, source: str = "github") -> requests.Response | None:
    """Make a GET request with basic rate limiting."""
    global _last_github_request
    if source == "github":
        elapsed = time.time() - _last_github_request
        if elapsed < 6.5:  # ~10 req/min for unauthenticated
            time.sleep(6.5 - elapsed)
        _last_github_request = time.time()
    try:
        resp = requests.get(url, headers=headers, params=params, timeout=15)
        if resp.status_code == 403 and "rate limit" in resp.text.lower():
            print(f"Warning: {source} rate limit hit, skipping", file=sys.stderr)
            return None
        return resp
    except requests.RequestException as e:
        print(f"Warning: {source} request failed: {e}", file=sys.stderr)
        return None


def search_github(query: str) -> dict:
    """Search GitHub repositories for the given query."""
    url = "https://api.github.com/search/repositories"
    params = {"q": query, "sort": "stars", "order": "desc", "per_page": 10}
    resp = _rate_limited_get(url, _github_headers(), params, source="github")

    if resp is None or resp.status_code != 200:
        return {"total_repos": 0, "top": [], "error": "GitHub search failed"}

    data = resp.json()
    total = data.get("total_count", 0)
    top = []
    for item in data.get("items", [])[:5]:
        top.append({
            "name": item.get("full_name", ""),
            "stars": item.get("stargazers_count", 0),
            "description": (item.get("description") or "")[:120],
            "url": item.get("html_url", ""),
            "source": "github",
        })
    return {"total_repos": total, "top": top}


def search_npm(query: str) -> dict:
    """Search npm registry for packages matching the query."""
    url = "https://registry.npmjs.org/-/v1/search"
    params = {"text": query, "size": 5}
    headers = {"User-Agent": "idea-validator/1.0"}
    resp = _rate_limited_get(url, headers, params, source="npm")

    if resp is None or resp.status_code != 200:
        return {"total_packages": 0, "top": [], "error": "npm search failed"}

    data = resp.json()
    total = data.get("total", 0)
    top = []
    for obj in data.get("objects", [])[:5]:
        pkg = obj.get("package", {})
        top.append({
            "name": pkg.get("name", ""),
            "description": (pkg.get("description") or "")[:120],
            "url": pkg.get("links", {}).get("npm", ""),
            "source": "npm",
        })
    return {"total_packages": total, "top": top}


def search_pypi(query: str) -> dict:
    """Search PyPI for packages matching the query."""
    # PyPI doesn't have an official search API; use the simple JSON endpoint via warehouse
    url = f"https://pypi.org/search/"
    # PyPI search is HTML-based; use the JSON API to check for exact package existence
    # and fall back to a web search approach
    # Instead, use the warehouse XML-RPC or just check the simple index
    # For reliability, search via the PyPI warehouse API
    headers = {"User-Agent": "idea-validator/1.0", "Accept": "application/json"}

    # Use the PyPI search via the JSON API (search by classifiers/keywords)
    # Since PyPI has no proper search API, we'll use a different approach:
    # Search GitHub for Python packages with the query
    url = "https://api.github.com/search/repositories"
    params = {"q": f"{query} language:python", "sort": "stars", "order": "desc", "per_page": 5}
    resp = _rate_limited_get(url, _github_headers(), params, source="github")

    if resp is None or resp.status_code != 200:
        return {"total_packages": 0, "top": [], "error": "PyPI search failed"}

    data = resp.json()
    total = min(data.get("total_count", 0), 1000)  # Cap at 1000
    top = []
    for item in data.get("items", [])[:5]:
        top.append({
            "name": item.get("full_name", ""),
            "stars": item.get("stargazers_count", 0),
            "description": (item.get("description") or "")[:120],
            "url": item.get("html_url", ""),
            "source": "pypi/github",
        })
    return {"total_packages": total, "top": top}


def compute_reality_signal(github: dict, npm: dict, pypi: dict) -> int:
    """Compute a 0-100 reality signal based on search results."""
    score = 0.0

    # GitHub: primary signal (0-60 points)
    gh_total = github.get("total_repos", 0)
    if gh_total > 0:
        # Log scale: 1 repo = ~5, 100 repos = ~25, 1000 = ~35, 10000 = ~45, 100000+ = ~55
        score += min(55, 5 + 12 * math.log10(max(gh_total, 1)))

    # Star concentration: top repo with many stars = mature space (+0-20)
    top_stars = 0
    for item in github.get("top", []):
        top_stars = max(top_stars, item.get("stars", 0))
    if top_stars > 0:
        # 100 stars = ~5, 1000 = ~10, 10000 = ~15, 50000+ = ~20
        score += min(20, 3 * math.log10(max(top_stars, 1)))

    # npm presence: +0-10
    npm_total = npm.get("total_packages", 0)
    if npm_total > 0:
        score += min(10, 2 + 2.5 * math.log10(max(npm_total, 1)))

    # PyPI presence: +0-10
    pypi_total = pypi.get("total_packages", 0)
    if pypi_total > 0:
        score += min(10, 2 + 2.5 * math.log10(max(pypi_total, 1)))

    return max(0, min(100, round(score)))


def get_verdict(signal: int) -> str:
    """Return a human-readable verdict for the reality signal."""
    if signal >= 70:
        return "Very crowded space -- differentiate or reconsider"
    elif signal >= 30:
        return "Moderate competition -- find a niche angle"
    else:
        return "Open space -- good opportunity for a new entrant"


def generate_pivot_hints(query: str, github: dict) -> list[str]:
    """Generate generic pivot suggestions based on the query and results."""
    hints = []
    hints.append("Focus on a specific language, framework, or ecosystem")
    hints.append("Target a niche industry (finance, healthcare, education, compliance)")
    hints.append("Build for a specific workflow or integration point")

    top_items = github.get("top", [])
    if top_items:
        # If top repos are general-purpose, suggest specialization
        hints.append("Specialize where existing tools are too generic")
    if github.get("total_repos", 0) > 1000:
        hints.append("Consider a developer tool or plugin for an existing popular project")

    return hints[:5]


def main():
    parser = argparse.ArgumentParser(
        description="Validate a project idea by scanning GitHub, npm, and PyPI"
    )
    parser.add_argument(
        "--query", "-q",
        required=True,
        help="The idea or project description to validate"
    )
    parser.add_argument(
        "--depth", "-d",
        choices=["quick", "deep"],
        default="deep",
        help="Search depth: quick (GitHub only) or deep (GitHub + npm + PyPI)"
    )

    args = parser.parse_args()
    query = args.query

    print(f"Validating idea: {query}", file=sys.stderr)
    print(f"Depth: {args.depth}", file=sys.stderr)

    # Search GitHub (always)
    print("Searching GitHub...", file=sys.stderr)
    github_results = search_github(query)

    # Search npm and PyPI (deep mode only)
    npm_results = {"total_packages": 0, "top": []}
    pypi_results = {"total_packages": 0, "top": []}

    if args.depth == "deep":
        print("Searching npm...", file=sys.stderr)
        npm_results = search_npm(query)
        print("Searching PyPI (via GitHub Python repos)...", file=sys.stderr)
        pypi_results = search_pypi(query)

    # Compute signal
    signal = compute_reality_signal(github_results, npm_results, pypi_results)
    verdict = get_verdict(signal)
    pivot_hints = generate_pivot_hints(query, github_results)

    # Build top competitors list (deduplicated, sorted by stars)
    all_top = []
    seen = set()
    for source_results in [github_results, npm_results, pypi_results]:
        for item in source_results.get("top", []):
            key = item.get("name", "")
            if key and key not in seen:
                seen.add(key)
                all_top.append(item)
    all_top.sort(key=lambda x: x.get("stars", 0), reverse=True)

    result = {
        "query": query,
        "reality_signal": signal,
        "verdict": verdict,
        "sources": {
            "github": {
                "total_repos": github_results.get("total_repos", 0),
                "top": github_results.get("top", []),
            },
            "npm": {
                "total_packages": npm_results.get("total_packages", 0),
                "top": npm_results.get("top", []),
            },
            "pypi": {
                "total_packages": pypi_results.get("total_packages", 0),
                "top": pypi_results.get("top", []),
            },
        },
        "top_competitors": all_top[:5],
        "pivot_hints": pivot_hints,
    }

    # Output JSON to stdout
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
