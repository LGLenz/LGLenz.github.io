# Operating Model — CI/CD and Deployment Governance

This document is the single source of truth for how changes flow from an
assistant-drafted edit to a verified production deployment of
**https://lglenz.github.io/** — the personal landing page repo.

The intent is to move governance from "Copilot/assistant remembers to run
the right thing" to **mandatory, codified workflows enforced by GitHub
branch protection, environments, and scheduled smoke tests**.

This repo is the simplest tier of the reusable governance model: it is a
**root user Pages site** (`<user>.github.io`), with no custom domain,
no DNS-as-code, and no CNAME — just `index.html` deployed to
`https://lglenz.github.io/`.

## 1. Flow at a glance

```
  Copilot / assistant drafts change on a branch
                |
                v
        Open Pull Request to main
                |
                v
   ┌────────────────────────────────────┐
   │  PR Mandatory Checks               │  ← required by branch protection
   │  - install-validation              │
   │  - build-validation                │
   │  - lint                            │
   │  - link-sanity                     │
   │  - secrets-config                  │
   └────────────────────────────────────┘
                |
                v
        Reviewer approves & merges
                |
                v
   ┌────────────────────────────────────┐
   │  Deploy GitHub Pages (Production)  │  ← uses `production` environment
   │  - build artifact                  │     (optional reviewers/wait timer)
   │  - actions/deploy-pages@v4         │     records GitHub deployment status
   │  - enforce HTTPS                   │
   └────────────────────────────────────┘
                |
                v
   ┌────────────────────────────────────┐
   │  Site Health (post-deploy)         │  ← triggered by workflow_run
   │  - HTTPS / TLS / status / title    │     + scheduled every 6h
   │  - https://lglenz.github.io/       │     + manual workflow_dispatch
   └────────────────────────────────────┘
```

## 2. Workflow inventory

| Workflow file                          | Trigger                                       | Purpose                                                  |
|----------------------------------------|-----------------------------------------------|----------------------------------------------------------|
| `.github/workflows/pr-checks.yml`      | `pull_request`, `push:main`, `workflow_dispatch` | Mandatory PR checks (jobs listed below).             |
| `.github/workflows/deploy-pages.yml`   | `push:main`, `workflow_dispatch`              | Build + deploy Pages artifact via official actions; records deployment status against the `production` environment. |
| `.github/workflows/site-health.yml`    | `workflow_dispatch`, `schedule` (6h), `workflow_run` (after deploy) | HTTP, TLS, and title smoke test of the live site. |

## 3. PR Mandatory Checks — required-status-checks list

The following job names from `pr-checks.yml` should be marked **required**
in the `main` branch protection rule:

- `Install / tooling validation`
- `Build / artifact validation`
- `Lint / static validation`
- `Link / site artifact sanity`
- `No-secrets / config sanity`

To configure (Settings → Branches → Branch protection rules → `main`):

1. ✅ Require a pull request before merging
2. ✅ Require status checks to pass before merging
3. ✅ Require branches to be up to date before merging
4. Add the job names above to the required-checks list.
5. ✅ Require linear history (recommended).
6. ✅ Require conversation resolution before merging (recommended).

## 4. Pages source — one-time setting

Because this repo is a root user Pages site, GitHub Pages may currently
be configured to **deploy from a branch** (the default). To use the
new workflow as the deployment source:

**Settings → Pages → Build and deployment → Source → "GitHub Actions"**

Until this is changed, `deploy-pages.yml` will fail with a clear error
at the `actions/deploy-pages` step (because the repo is not yet wired
for workflow-source deploys), but the existing branch-source deploy
continues to publish `https://lglenz.github.io/` — there is no
downtime risk from merging this PR.

Once the source is switched to GitHub Actions, every `push:main` and
every `workflow_dispatch` will produce a tracked deployment.

## 5. Production environment

The deploy workflow targets a GitHub **environment** named `production`.
Configure it under **Settings → Environments → New environment → production**:

- **Required reviewers**: add the maintainers who should approve a deploy.
- **Wait timer**: optional, e.g. 5 minutes to allow a final cancel.
- **Deployment branches**: restrict to `main`.

When `deploy-pages.yml` runs, GitHub will:

1. Record a deployment with status `in_progress`.
2. Block on the environment's approval rules (if any).
3. Run the deploy.
4. Update the deployment status to `success` or `failure`.

This eliminates the "deployments tab is stale" problem because every
`push:main` and every manual dispatch produces a tracked deployment.

## 6. Post-deploy site health

`site-health.yml` runs:

- automatically after `deploy-pages.yml` completes (via `workflow_run`),
- on a 6-hour cron schedule,
- on demand via `workflow_dispatch`.

What it checks, for each target URL:

1. **DNS** — `dig` returns at least one A/AAAA/CNAME record.
2. **TLS** — `openssl s_client` completes without verification errors.
3. **HTTP** — `curl` returns a 2xx/3xx status within 15s.
4. **Title** — response body contains a `<title>` mentioning "Elias Lenz"
   or "LGLenz".

Targets:

| Label       | URL                                | Required?       |
|-------------|------------------------------------|-----------------|
| root-pages  | https://lglenz.github.io/          | yes             |

When the scheduled run fails, an issue is opened with label `site-health`.
(The label can be created in advance — if it does not exist the issue
creation step warns but does not block.)

## 7. Operating principles

- **Copilot/assistant drafts; humans approve.** The assistant opens a PR;
  PR checks run automatically; a human reviewer merges.
- **Branch protection is the enforcer, not memory.** No reliance on the
  assistant "remembering" to run checks — they run because GitHub
  requires them.
- **Production deploys use environment approvals.** Manual deploys via
  `workflow_dispatch` go through the same approval gate as automatic
  push-to-main deploys.
- **Smoke tests verify reality.** A green deploy that produces a broken
  site fails the post-deploy `site-health` workflow and opens an issue.
- **No secrets in PR checks.** All required PR checks are read-only and
  run on forks safely.

## 8. Troubleshooting

| Symptom                                          | Likely cause                                                       | Where to look |
|--------------------------------------------------|--------------------------------------------------------------------|---------------|
| Deployments tab is stale                         | A previous Pages workflow failed without recording a deployment, or Pages source is still set to "Deploy from a branch". | Settings → Pages → Build and deployment + `deploy-pages.yml` run log. |
| `deploy-pages.yml` fails at the deploy step      | Pages source not yet set to "GitHub Actions".                      | Settings → Pages → Build and deployment → Source = "GitHub Actions". |
| `site-health` HTTP check fails                   | Pages outage, broken `index.html`, or DNS issue.                   | `site-health.yml` run log. |
| PR check `No-secrets / config sanity` fails      | A secret-shaped string was committed.                              | Job log lists the file and pattern. |

## 9. How to make changes safely

```bash
# 1. Start from main.
git switch main && git pull

# 2. Branch.
git switch -c feat/your-change

# 3. Edit. Commit. Push.
git push -u origin feat/your-change

# 4. Open a PR. Mandatory checks run automatically.
# 5. After approval + merge, deploy-pages.yml runs.
# 6. site-health.yml runs post-deploy and on schedule.
```
