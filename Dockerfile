# Build upstream Paperclip from a pinned ref.
FROM node:22-bookworm AS paperclip-build
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

ARG PAPERCLIP_REPO=https://github.com/paperclipai/paperclip.git
ARG PAPERCLIP_REF=v2026.609.0

WORKDIR /paperclip
RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" "${PAPERCLIP_REPO}" .

# Downstream patches applied on top of the pinned upstream ref.
# KIN-4355: split issue:comment from issue:mutate so mention-woken non-assignee
# agents can comment on the issue that woke them. Verified to apply cleanly
# against PAPERCLIP_REF=v2026.609.0. If you bump PAPERCLIP_REF, re-verify each
# patch in patches/ still applies (the build fails loudly here if one doesn't).
COPY patches/ /tmp/paperclip-patches/
RUN for p in /tmp/paperclip-patches/*.patch; do \
        echo "Applying $p" && git apply --verbose "$p"; \
    done

RUN pnpm install --frozen-lockfile
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js

# Runtime image (direct Paperclip server, no wrapper).
FROM node:22-bookworm
ENV NODE_ENV=production
ENV CLAUDE_CODE_BUBBLEWRAP=1
# Match upstream production image defaults (paperclipai/paperclip Dockerfile) so
# agent tooling, OpenCode, and config paths behave the same in containers.
ENV HOME=/paperclip \
    PAPERCLIP_INSTANCE_ID=default \
    PAPERCLIP_CONFIG=/paperclip/instances/default/config.json \
    OPENCODE_ALLOW_ALL_MODELS=true

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

WORKDIR /app
COPY --from=paperclip-build /paperclip /app

WORKDIR /wrapper
COPY package.json /wrapper/package.json
RUN npm install --omit=dev && npm cache clean --force
COPY src /wrapper/src
COPY scripts/entrypoint.sh /wrapper/entrypoint.sh
COPY scripts/bootstrap-ceo.mjs /wrapper/template/bootstrap-ceo.mjs
RUN chmod +x /wrapper/entrypoint.sh

# Optional local adapters/tools parity with upstream Dockerfile.
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai
RUN npm install --global --omit=dev tsx
RUN mkdir -p /paperclip \
    && chown -R node:node /app /paperclip /wrapper

# Railway sets PORT at runtime and this process binds to it.
# Entrypoint runs as root, fixes /paperclip volume permissions, then execs as node.
EXPOSE 3100
ENTRYPOINT ["/wrapper/entrypoint.sh"]
CMD ["node", "/wrapper/src/server.js"]
