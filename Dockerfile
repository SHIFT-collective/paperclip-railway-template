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
ARG PAPERCLIP_REF=v2026.626.0

WORKDIR /paperclip
RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" "${PAPERCLIP_REPO}" .

# Downstream patches applied on top of the pinned upstream ref.
# KIN-4355: split issue:comment from issue:mutate so mention-woken non-assignee
# agents can comment on the issue that woke them.
# KIN-4697: add GET /api/companies/:companyId/pending-interactions + the
# listPendingForCompany service method (Better Actions Phase 1 backend) so the
# inbox can surface pending board decisions outside their thread.
# KIN-4699: add the Decisions section (inbox "mine" tab) + inline yes/no rows +
# Quick view slide-over (Better Actions Phase 1 UI), built on the KIN-4697
# endpoint; UI-only, reuses the existing interaction accept/reject/respond routes.
# KIN-4700: pinned "Pending actions" strip on the issue detail page (Better
# Actions Phase 2 UI), reusing the Phase 1 decision row.
# KIN-4701: responder/approver binding backend (Better Actions Phase 3) — adds
# nullable responder_user_id / approver_user_id + responderUserId=me filtering.
# KIN-4780: "Waiting on you — Approver" badge, "Needs my decision" filter, and
# derived "Awaiting board" chip (Better Actions Phase 3 UI), built on KIN-4701's
# responder binding; UI-only.
# All verified to apply cleanly against PAPERCLIP_REF=v2026.618.0. If you bump
# PAPERCLIP_REF, re-verify each patch in patches/ still applies (the build fails
# loudly here if one doesn't).
COPY patches/ /tmp/paperclip-patches/
# `set -e` + explicit exit so a single failed `git apply` aborts the build. The
# previous bare `for` loop returned only the LAST patch's exit code, so a patch
# that failed mid-list (e.g. after a PAPERCLIP_REF bump) was masked by a later
# patch that still applied — the build went green with the change silently missing.
RUN set -e; for p in /tmp/paperclip-patches/*.patch; do \
        echo "Applying $p"; \
        git apply --verbose "$p" || { echo "ERROR: patch $p failed to apply against ${PAPERCLIP_REF}" >&2; exit 1; }; \
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
    python3 \
    python3-pip \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

# KIN-4879: bake duckdb into the runtime image so it survives container
# rebuilds (/usr is not on the persistent /paperclip volume). Used by the
# kk_permissions weekly permissions-cache refresh routine (KIN-4878).
# Keep this version aligned with kk_permissions/requirements.txt (bump both
# together). --break-system-packages is required on Debian bookworm (PEP 668).
RUN pip3 install --no-cache-dir --break-system-packages duckdb==1.5.3

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
