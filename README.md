# LGLenz.github.io
Personal landing page — Elias Lenz · Security, Strategy, Policy-as-Code

Live site: <https://lglenz.github.io/>

## CI/CD — Operating Model

Governance lives in GitHub Actions, branch protection, and environment
approvals — not in assistant memory. See
[`docs/Operating-Model.md`](docs/Operating-Model.md) for the full picture.

Flow:

1. **Copilot/assistant drafts** changes on a feature branch and opens a PR.
2. **PR mandatory checks** run automatically (`.github/workflows/pr-checks.yml`):
   install/tooling validation, build/artifact validation, lint, link/site
   sanity, and no-secrets/config sanity. Branch protection should mark
   these jobs as required for merging to `main`.
3. **Production deployment** (`.github/workflows/deploy-pages.yml`) runs on
   `push:main` and on `workflow_dispatch`, targets the `production`
   GitHub environment (which can require human approval), and records a
   GitHub deployment status for every run.
4. **Post-deploy smoke tests** (`.github/workflows/site-health.yml`)
   verify HTTP status, TLS, and page title for `https://lglenz.github.io/`.
   Runs after every deploy, on a 6-hour schedule, and on demand. Failures
   on scheduled runs open a tracking issue.

One-time settings required after merge — see `docs/Operating-Model.md`
for details:

- Settings → Pages → Build and deployment → Source = **GitHub Actions**
- Settings → Environments → new environment **production**
- Settings → Branches → branch protection on `main` with the PR check
  job names marked as required.

## Project structure

```
.
├── index.html              # Landing page
├── README.md
├── docs/
│   └── Operating-Model.md  # CI/CD + deployment governance
├── scripts/
│   └── site_health.sh      # HTTP/TLS/title smoke probe
└── .github/
    └── workflows/
        ├── pr-checks.yml          # Mandatory checks for PRs/pushes
        ├── deploy-pages.yml       # Production GitHub Pages deploy
        └── site-health.yml        # Post-deploy + scheduled smoke tests
```
