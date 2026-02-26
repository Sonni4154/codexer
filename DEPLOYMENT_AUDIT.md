# Deployment Audit (current repository state)

## Fixed in this pass

1. **Hardcoded secret in `docker-compose.yml`**
   - Cloudflared tunnel token was committed inline.
   - Replaced with `${CLOUDFLARED_TOKEN}`.

2. **`n8n_sync` service was non-functional placeholder**
   - Implemented workflow sync against `/api/v1/workflows`.
   - Supports create/update by workflow name, periodic sync loop, and error logging.

3. **Indexer/parser services ignored configured Ollama endpoint**
   - Embedded calls used default local endpoint instead of compose-provided host.
   - Added explicit Ollama client host configuration.

4. **`CODE_PATHS` mismatch**
   - Compose sets `CODE_PATHS` for indexer/chunker.
   - Scripts only read `WATCH_PATHS`.
   - Added fallback support for both.

5. **Missing baseline repo hygiene**
   - Added `.gitignore` and `.env.example` for safer deployment defaults.

## Remaining risks to address before production

1. **Historical secrets likely present in git history**
   - Even after removing hardcoded values in current files, old commits may still expose secrets.
   - Rotate all exposed credentials/tokens and consider history rewrite if repo is shared externally.

2. **External network dependency**
   - Compose requires `backend_network`, `database_network`, and `ai_network` as pre-existing external networks.
   - Ensure they are provisioned by IaC/bootstrap scripts for repeatable deploys.

3. **No CI validation in repository**
   - No automated lint/test/deploy checks are present.
   - Add lightweight CI: Python syntax/lint, compose validation, and smoke checks.

4. **No health endpoint check for custom python services**
   - `code_parser`, `code_indexer`, `ast_chunker`, `n8n_sync` run loops without service health probes.
   - Consider adding HTTP health endpoints and compose healthchecks.
