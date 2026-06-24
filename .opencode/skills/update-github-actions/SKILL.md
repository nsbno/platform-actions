---
name: update-github-actions
description: Update external GitHub Actions to their latest versions. Use when someone asks to "update github actions", "bump action versions", "update action dependencies", "upgrade workflow dependencies", or similar. Fetches the latest releases from GitHub, checks for known vulnerabilities, reviews breaking changes, and updates workflow files with correct version pins.
---

# Update GitHub Actions

Updates external GitHub Actions dependencies across all workflow files in `.github/workflows/` (and any `action.yml` files under `.github/actions/` that call external actions).

Read [references/workflow.md](references/workflow.md) **fully before proceeding** — it contains the complete step-by-step process: pinning rules, how to discover actions, how to fetch the latest release and commit SHA, vulnerability checks, breaking change analysis, and how to apply updates.
