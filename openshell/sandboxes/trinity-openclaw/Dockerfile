# syntax=docker/dockerfile:1.4

# Trinity OpenClaw sandbox for OpenShell
#
# Extends the community OpenClaw sandbox with Trinity's extensions,
# skills, cron-templates, workspace seed, and bootstrap script.
#
# Build:
#   docker build -t trinity-openclaw-sandbox \
#     --build-arg BASE_IMAGE=ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest .
#
# Run:
#   openshell sandbox create --from ./openshell/sandboxes/trinity-openclaw

ARG BASE_IMAGE=ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest
FROM ${BASE_IMAGE}

USER root

# Upgrade OpenClaw to latest
RUN npm install -g openclaw@latest

# Document processing utilities (matching src/Dockerfile.openclaw)
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    pandoc \
    python3 python3-pip python3-venv \
    imagemagick \
    tesseract-ocr \
    libreoffice-writer-nogui \
    socat \
    && python3 -m venv /opt/doctools \
    && /opt/doctools/bin/pip install --no-cache-dir \
       pdfplumber PyPDF2 python-docx Pillow pytesseract \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/doctools/bin:$PATH"

# uv for Python script execution (used by skills)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Playwright Chromium for browser tool support
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2 libatspi2.0-0 \
    fonts-liberation fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji \
    xdg-utils wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && PLAYWRIGHT_CLI=$(find /usr/local/lib/node_modules -name "cli.js" -path "*/playwright-core/*" 2>/dev/null | head -1) \
    && if [ -n "$PLAYWRIGHT_CLI" ]; then \
         node "$PLAYWRIGHT_CLI" install chromium; \
       else \
         npx playwright install chromium || true; \
       fi

# Move Playwright browsers to sandbox user's cache
RUN mkdir -p /sandbox/.cache && \
    if [ -d /root/.cache/ms-playwright ]; then \
      cp -r /root/.cache/ms-playwright /sandbox/.cache/ms-playwright; \
    fi

# Seed directory for Trinity-specific content
RUN mkdir -p /opt/trinity-seed/extensions/canvas-bridge \
             /opt/trinity-seed/extensions/file-upload \
             /opt/trinity-seed/skills \
             /opt/trinity-seed/cron-templates \
             /opt/trinity-seed/workspace

# Copy Trinity extensions, skills, cron-templates, workspace seed, and bootstrap
# These are COPYed from the repo relative to the build context
COPY extensions/canvas-bridge/ /opt/trinity-seed/extensions/canvas-bridge/
COPY extensions/file-upload/ /opt/trinity-seed/extensions/file-upload/
COPY skills/ /opt/trinity-seed/skills/
COPY cron-templates/ /opt/trinity-seed/cron-templates/
COPY workspace-seed/ /opt/trinity-seed/workspace/
COPY bootstrap-trinity.sh /usr/local/bin/bootstrap-trinity
RUN chmod +x /usr/local/bin/bootstrap-trinity

# Pre-install extensions into the OpenClaw state directory
RUN mkdir -p /sandbox/.openclaw/extensions/canvas-bridge \
             /sandbox/.openclaw/extensions/file-upload && \
    cp -a /opt/trinity-seed/extensions/canvas-bridge/. /sandbox/.openclaw/extensions/canvas-bridge/ && \
    cp -a /opt/trinity-seed/extensions/file-upload/. /sandbox/.openclaw/extensions/file-upload/

# Copy Trinity's sandbox policy (extends base OpenClaw policy)
COPY policy.yaml /etc/openshell/policy.yaml

# Fix ownership
RUN chown -R sandbox:sandbox /sandbox/.openclaw /sandbox/.cache /opt/trinity-seed

USER sandbox

ENTRYPOINT ["/bin/bash"]
