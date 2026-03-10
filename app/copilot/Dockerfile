FROM node:20-bookworm-slim

WORKDIR /app
ENV PATH="/app/node_modules/.bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ripgrep ca-certificates bash curl \
    && curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" \
    && chmod +x kubectl && mv kubectl /usr/local/bin/ \
    && rm -rf /var/lib/apt/lists/*

COPY app/copilot/package.json app/copilot/package-lock.json* ./
RUN npm ci --omit=dev

COPY app/copilot/src ./src

RUN mkdir -p /workspace/.opencode/tools /workspace/.opencode/skills
COPY opencode.jsonc /workspace/opencode.jsonc
COPY opencode.jsonc /workspace/opencode.json
COPY app/copilot/AGENT.md /workspace/AGENT.md
COPY app/copilot/AGENT.md /workspace/AGENTS.md
COPY app/copilot/tools/ /workspace/.opencode/tools/
COPY .opencode/skills/ /workspace/.opencode/skills/

ENV COPILOT_WORKSPACE=/workspace
ENV COPILOT_PORT=18802
ENV OPENCODE_PORT=4096

EXPOSE 18802

CMD ["node", "src/index.js"]
