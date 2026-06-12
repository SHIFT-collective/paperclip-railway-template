# Template Changelog

## 2026-06-12

- Added: downstream patch `patches/KIN-4697-pending-interactions.patch`, applied at build time on top of pinned upstream `v2026.609.0`. Adds `GET /api/companies/:companyId/pending-interactions` (company-scoped, `company_scope:read`) and the `issueThreadInteractionService.listPendingForCompany()` method — the backend slice of the approved KIN-4606 "Better Actions" plan (Phase 1). Returns pending board-facing issue-thread interactions enriched with issue identifier/title/status, kind, title/summary, requesting agent, age, the plan/document target for plan-bound confirmations, and a stable `interaction-<id>` anchor; excludes terminal/hidden issues and resolved rows. Additive and read-only: no schema migration, no writes, existing accept/reject/respond routes (and `wake_assignee` continuation) unchanged. Responder binding (`responderUserId`/`approverUserId`) is Phase 3. Verified `git apply` clean against `v2026.609.0`; typecheck + route-coverage and service tests pass (the DB integration test runs in CI under a non-root user). Recommend upstreaming to `paperclipai/paperclip` and dropping the patch once a release contains it. See KIN-4697 (parent KIN-4606).

## 2026-06-11

- Added: downstream patch `patches/KIN-4355-issue-comment-authz.patch`, applied at build time on top of pinned upstream `v2026.609.0`. Splits a new `issue:comment` authorization action from `issue:mutate` so mention-woken non-assignee agents can comment on the issue that woke them (fixes the 403 "outside this actor's authorization boundary" on `POST /api/issues/:id/comments`). State-changing paths (`reopen`/`resume`/`interrupt`, non-comment PATCH fields, checkout) remain gated. Verified `git apply` clean against `v2026.609.0`; route tests pass (73 passed, 0 failed). Recommend upstreaming to `paperclipai/paperclip` and dropping the patch once a release contains it. See KIN-4355.

## 2026-06-10

- Changed: Paperclip pin `v2026.517.0` → `v2026.609.0` (routine upstream uptake to latest stable; see [paperclip v2026.609.0 release notes](https://github.com/paperclipai/paperclip/releases/tag/v2026.609.0) and [compare v2026.517.0...v2026.609.0](https://github.com/paperclipai/paperclip/compare/v2026.517.0...v2026.609.0)). **Upgrade note:** this bump includes 13 forward database migrations; they applied cleanly against an external Railway Postgres during an in-place upgrade of the live instance (no manual `CREATE EXTENSION` required). Take a Postgres + storage backup before redeploying.

## 2026-05-23

- Changed: Paperclip pin `v2026.416.0` → `v2026.517.0` (routine upstream uptake; see [paperclip v2026.517.0 release notes](https://github.com/paperclipai/paperclip/releases/tag/v2026.517.0)).
- Added: `.github/workflows/bump-paperclip.yml` — weekly scheduled workflow (also `workflow_dispatch`) that runs `scripts/bump-paperclip-ref.mjs` and opens a PR when a new upstream Paperclip release is available.

## 2026-04-17

- Fixed: WebSocket proxy upstream errors no longer crash the Node process (#6, duplicate #7) — `http-proxy` can pass a socket on WS failures, which has no `writeHead`; the wrapper now sends JSON 503 only for HTTP responses and destroys the socket otherwise.
- Changed: Paperclip pin `v2026.325.0` → `v2026.416.0` (latest stable at bump time; routine upstream uptake). **Upgrade note:** upstream v2026.416.0 adds migrations including `pg_trgm`; embedded Postgres in this template should allow `CREATE EXTENSION`, but external DB users may need DBA to run `CREATE EXTENSION IF NOT EXISTS pg_trgm;` before upgrade — see [paperclip v2026.416.0 release notes](https://github.com/paperclipai/paperclip/releases/tag/v2026.416.0).
- Changed: Runtime image aligned with [upstream Paperclip production Dockerfile](https://github.com/paperclipai/paperclip/blob/master/Dockerfile) — `HOME=/paperclip`, `PAPERCLIP_INSTANCE_ID`, `PAPERCLIP_CONFIG`, `OPENCODE_ALLOW_ALL_MODELS=true`, and apt packages `git`, `openssh-client`, `jq`, `ripgrep` (agent/git tooling parity).

## 2026-04-02

- Fixed: Claude Code adapter fails with `--dangerously-skip-permissions cannot be used with root/sudo privileges` (#4)
  - Set `CLAUDE_CODE_BUBBLEWRAP=1` in Dockerfile — tells Claude Code it is running inside a container sandbox, bypassing the redundant root check while Docker's own isolation remains active
  - Replaced `gosu` with `setpriv --inh-caps=-all` in entrypoint to properly drop inherited Linux capabilities
  - Removed `gosu` package from Dockerfile (no longer needed; `setpriv` is part of the base image)
