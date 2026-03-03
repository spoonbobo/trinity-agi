---
name: idea-validator
description: Validate project ideas before building by scanning GitHub, npm, and PyPI for existing competitors — returns a reality_signal score (0-100) indicating how crowded the space is.
homepage: https://github.com/trinityagi/trinity-agi
metadata:
  {
    "openclaw":
      {
        "emoji": "🔍",
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

# Idea Validator

Scan real data sources before building anything new. Returns a `reality_signal` score (0-100) indicating how crowded the space is, plus top competitors and pivot suggestions.

## When to Activate

**IMPORTANT: Run this automatically before starting any new project, feature, or tool.**

Also trigger when the user:
- Says "build me a [tool/app/service]"
- Asks "is there already a [thing] out there?"
- Wants to validate a project idea or check for competitors
- Mentions starting a new side project or product

## Usage

```bash
uv run {baseDir}/scripts/validate_idea.py --query "AI code review tool"
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--query` / `-q` | The idea or project description to validate | (required) |
| `--depth` / `-d` | Search depth: `quick` (GitHub only) or `deep` (GitHub + npm + PyPI) | `deep` |

### Example Output

```json
{
  "query": "AI code review tool",
  "reality_signal": 82,
  "verdict": "Very crowded space — differentiate or reconsider",
  "sources": {
    "github": { "total_repos": 1847, "top": [...] },
    "npm": { "total_packages": 23, "top": [...] },
    "pypi": { "total_packages": 15, "top": [...] }
  },
  "top_competitors": [
    { "name": "reviewdog/reviewdog", "stars": 9104, "description": "Automated code review tool", "source": "github" },
    { "name": "sourcery-ai/sourcery", "stars": 1523, "description": "AI-powered code reviewer", "source": "github" }
  ],
  "pivot_hints": [
    "Focus on a specific language or framework",
    "Target a niche industry (finance, healthcare, compliance)",
    "Build for a specific workflow (PR review, pre-commit, IDE integration)"
  ]
}
```

## Decision Thresholds

After running the validator, follow these rules:

| Score | Action |
|-------|--------|
| **> 70** (High) | **STOP.** Report top 3 competitors with star counts. Ask the user if they want to proceed, pivot, or abandon. |
| **30–70** (Medium) | Show results and pivot hints. Suggest a niche angle that existing projects don't cover. |
| **< 30** (Low) | Proceed to build. Mention that the space is open. |

Always show the `reality_signal` score and top competitors before writing any code.

## Interpreting Results

- **High signal (>70)** doesn't mean "don't build" — it means "differentiate or don't bother." The top players are likely mature and well-funded.
- **Low signal (<30)** means genuine white space. Solo builders have the best odds here.
- **Medium signal (30-70)** is where nuance matters — look at the pivot hints for angles existing projects miss.

## Variations

- **Batch validation**: Before a hackathon, validate a list of ideas and rank by `reality_signal` — lowest score = most original opportunity.
- **Quick mode**: Use `--depth quick` for a fast GitHub-only check when you just need a rough signal.
- **Pre-build gate**: Add this to your workflow so it runs automatically before any "build me X" request.

## Tips

- The `reality_signal` is based on real data (repo counts, star distributions, package existence), not LLM guessing.
- Public APIs have rate limits — GitHub allows 10 requests/min unauthenticated. For heavy use, set a `GITHUB_TOKEN` env var.
- A project with 50k+ stars in the space is a strong signal — but it also validates the market.
- The script uses only public APIs with no authentication required for basic usage.
