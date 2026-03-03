---
name: side-hustler
description: End-to-end side hustle builder — researches your market, validates the idea, builds a product or landing page, sets up sales flow, and markets on social media while you sleep.
homepage: https://github.com/trinityagi/trinity-agi
metadata:
  {
    "openclaw":
      {
        "emoji": "🚀",
      },
  }
---

# Side Hustler Builder

Turn an idea into a launched product without quitting your day job.
The agent handles market research, product building, landing pages, sales setup, and marketing — working the hours you can't.

## When to Activate

Trigger this skill when the user:
- Has a side project or business idea they want to launch
- Asks "help me build and launch [product/service]"
- Wants to turn an idea into something real but doesn't know where to start
- Mentions wanting to make money from a side project
- Says something like "I have this idea but no time to build it"

## Workflow Overview

The side hustle build follows these phases. Run them sequentially, checking in with the user at each gate.

### Phase 1: Idea Validation

**Before doing anything else**, validate the idea using the idea-validator skill:

```bash
uv run /path/to/skills/idea-validator/scripts/validate_idea.py --query "[user's idea]"
```

- If `reality_signal > 70`: Show competitors and suggest differentiation angles. Ask user how to proceed.
- If `reality_signal 30-70`: Show the landscape and suggest a niche. Proceed with the niche angle.
- If `reality_signal < 30`: Green light — the space is open.

### Phase 2: Market Research

Use web search to gather:

1. **Target audience**: Who has this problem? Where do they hang out online?
2. **Existing solutions**: What are people currently using? What do they complain about?
3. **Pricing signals**: What do competitors charge? What pricing model works?
4. **Distribution channels**: Where can you reach the target audience?

Compile findings into a structured brief and present to the user before building.

### Phase 3: Product Building

Based on the idea type, build the appropriate artifact:

#### For Digital Products / SaaS
- Use the coding-agent skill (if available) to write the code
- Start with an MVP — the minimum that delivers value
- Focus on the core feature, skip nice-to-haves

#### For Landing Pages
- Generate a complete HTML/CSS landing page with:
  - Clear value proposition headline
  - Problem/solution framing
  - Feature highlights
  - Social proof section (placeholder if no testimonials yet)
  - Call-to-action (email signup, purchase, waitlist)
  - Mobile-responsive design

#### For Content Products (courses, ebooks, templates)
- Create the outline and first sections
- Design the table of contents
- Write compelling copy for the sales page

#### For Service Businesses
- Write the service offering document
- Create a pricing page
- Draft outreach templates

### Phase 4: Sales & Payment Setup

Guide the user through setting up the revenue flow:

1. **Payment processor**: Recommend Stripe, Gumroad, or LemonSqueezy based on product type
2. **Pricing strategy**: Based on Phase 2 research, suggest pricing with rationale
3. **Sales page copy**: Write persuasive copy following proven frameworks (PAS, AIDA)
4. **Email capture**: Set up a waitlist or lead magnet if the product isn't ready yet

Provide step-by-step setup instructions for the chosen platform.

### Phase 5: Marketing & Launch

Create a marketing plan and initial assets:

1. **Launch announcement**: Draft posts for X/Twitter, Reddit, Product Hunt, Hacker News
2. **Content calendar**: Plan the first 2 weeks of social media posts
3. **SEO basics**: Suggest target keywords, write meta descriptions
4. **Outreach list**: Identify relevant communities, newsletters, and influencers
5. **Email sequence**: Draft a 3-email welcome/onboarding sequence

### Phase 6: Ongoing Operations

Set up automations for ongoing work:

```bash
# Daily social media post
cron add "0 10 * * *" "Create and post today's social media content for [product] based on the content calendar" --name "side-hustle-social"

# Weekly metrics check
cron add "0 9 * * 1" "Search for mentions of [product] online and compile a weekly metrics report" --name "side-hustle-metrics"

# Customer interaction monitoring
cron add "0 */4 * * *" "Check for new customer questions or feedback about [product] and draft responses" --name "side-hustle-support"
```

## Checkpoint Pattern

At each phase transition, check in with the user:

```
Phase [N] complete. Here's what I've done:
[Summary of deliverables]

Ready to move to Phase [N+1]: [Phase name]?
Or would you like to adjust anything first?
```

Never skip phases or make major decisions without user confirmation.

## Tips

- **Start with validation** — the biggest waste is building something nobody wants.
- **MVP mindset** — ship the smallest thing that works, then iterate.
- **Work overnight** — schedule content creation, research, and marketing tasks as crons so the agent works while the user sleeps.
- **Keep the user in control** — present options and recommendations, don't make unilateral decisions about pricing or strategy.
- The user likely has limited time — optimize for decisions they need to make vs. work the agent can handle autonomously.
- Store product details, target audience, and strategy decisions in memory for continuity across sessions.
- If the user already has a partial product, skip to the relevant phase instead of starting from scratch.
