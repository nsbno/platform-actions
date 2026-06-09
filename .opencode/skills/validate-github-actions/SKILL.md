---
name: validate-github-actions
description: Validate GitHub Actions workflow and action changes. Use when someone asks to "validate workflows", "check if my workflow changes are valid", "validate GitHub Actions", or has made edits to files under .github/workflows/ or .github/actions/. Also use when reviewing a PR that touches workflow or action files.
---

# Validate GitHub Actions

Checks that changes to workflow and action files are syntactically correct, that inputs passed to actions and reusable workflows match their declared definitions, and that no existing callers are broken.

Read [references/workflow.md](references/workflow.md) **fully before proceeding** — it contains the complete step-by-step validation process, what to check, and how to use official docs.
