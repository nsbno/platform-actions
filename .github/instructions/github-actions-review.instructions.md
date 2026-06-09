---
applyTo: ".github/workflows/*.yml,.github/actions/**/*.yml"
---

# GitHub Actions Validation Rules

This is a shared library — workflows and actions here are used by `@v2` consumers across
the organisation. Apply all rules below to every PR that modifies files in
`.github/workflows/` or `.github/actions/`.

Before writing any review comments, read
`.opencode/skills/validate-github-actions/references/workflow.md` in full. It is the
canonical validation guide for this project.

---

## 1. Input definitions

### `workflow_call` inputs (`on.workflow_call.inputs`)

- `type` is **required**: must be `boolean`, `number`, or `string`
- `required` is optional boolean
- `description` is optional but recommended
- `default` is optional; if `required: false` with no default, the value is
  `false` / `0` / `""` depending on type

### Composite action inputs (`inputs:` block)

- `description` is **required**
- `required` is optional boolean (default: `false`)
- `default` is optional string

---

## 2. Inputs passed to actions and called workflows

For every `with:` block in a step or job:

1. Locate the target definition (local action → read `action.yml`; local workflow → read
   the workflow file; external → check the pinned version tag)
2. Confirm every key in `with:` is declared as an input in the target
3. Confirm all `required: true` inputs (no `default`) are supplied by every caller
4. **Extra inputs passed to a reusable workflow are a hard error** — GitHub rejects the
   run at queue time. Flag as ❌ Error
5. Extra inputs passed to a composite action are silently ignored — flag as ⚠️ Warning

---

## 3. Backward compatibility (critical — `@v2` consumers cannot be updated centrally)

A change is **breaking** if it:
- Adds a `required: true` input with no `default` to an existing workflow or action
- Removes or renames an existing input
- Removes or renames an existing output
- Changes the semantics of an existing input in a non-additive way

A change is **safe** if it:
- Adds an input with `required: false` and a sensible `default`
- Adds a new optional output
- Adds a step that does not affect existing step ordering or outputs

To find callers within this repository:
```
grep -r "uses:.*<workflow-or-action-name>" .github/ --include="*.yml"
```

Callers in other repos cannot be audited from here. Always note this limitation when a
change touches inputs or outputs of a public workflow or action.

---

## 4. Design patterns

### No hardcoded infrastructure values

ECS cluster names, service names, S3 buckets, and CloudFront domains must come from
inputs or AWS SSM parameter lookups, never from literals embedded in workflow or action
files. The canonical lookup path is `/__deployment__/<repo>/<dir>/`.

Use `deployment/get-application-deployment-info` to resolve ECS/static-file targets
rather than writing raw SSM reads inline.

### Composite action vs. reusable workflow

- **Composite action** — logic that executes within a single job
- **Reusable workflow** — logic that spans multiple jobs (parallelism, job-level
  environment protection rules, separate secrets scoping)

Do not duplicate steps already provided by existing building blocks:
- Language toolchain setup → `tools/npm`, `tools/pnpm`, `tools/gradle`, `tools/terraform`
- Secret fetching → `helpers/aws/fetch-secrets-from-secrets-manager`
- Artifact download → `helpers/download-pipeline-artifact`
- ECS deployment → `deployment/deploy-ecs`

### PR SHA handling

Workflows that run on `pull_request` or `pull_request_target` events must use the PR head
commit SHA for `actions/checkout` and packaging steps:

```yaml
# Correct
ref: ${{ github.event.pull_request.head.sha }}

# Wrong — this is the temporary merge commit, not the PR branch
ref: ${{ github.sha }}
```

### `secrets: inherit` vs. explicit secret mapping

Reusable workflows called from within this repo can use `secrets: inherit`. Reusable
workflows intended to be called from external repos should declare explicit `secrets:`
inputs so callers know what is required.

### Expression syntax

- `${{ inputs.foo }}` — valid only if `inputs.foo` is declared at this workflow/action
  level
- `${{ secrets.FOO }}` — only available in jobs where `secrets: inherit` is set or the
  secret is explicitly mapped
- `${{ needs.job-id.outputs.foo }}` — valid only if `job-id` appears in `needs:` for
  this job
- `${{ github.event.pull_request.head.sha }}` — correct way to get PR head SHA

---

## 5. Security review

> **False-positive policy.** Only raise a security finding when you can describe a
> concrete, realistic exploit path. Do not report theoretical risks, vague concerns, or
> patterns that are already established in this codebase (they were accepted decisions,
> not new changes). One missed real issue is better than three noisy false positives that
> train reviewers to ignore comments.
>
> Authoritative reference for every check below:
> [GitHub Actions security hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)

### 5.1 Script injection — ❌ always flag if present

Embedding a GitHub event expression directly inside a `run:` step or an
`actions/github-script` body allows an attacker to inject arbitrary shell or JavaScript
by crafting an issue title, PR body, branch name, comment, etc.

**Vulnerable pattern:**
```yaml
- run: echo "Branch is ${{ github.head_ref }}"
- run: echo "${{ github.event.issue.title }}"
- uses: actions/github-script@v7
  with:
    script: |
      github.issues.createComment({ body: "${{ github.event.comment.body }}" })
```

**Safe pattern — assign to an env var first, then reference via shell variable:**
```yaml
- env:
    BRANCH: ${{ github.head_ref }}
  run: echo "Branch is $BRANCH"
```

User-controlled context values include (non-exhaustive):
`github.head_ref`, `github.base_ref`, `github.event.issue.title`,
`github.event.issue.body`, `github.event.pull_request.title`,
`github.event.pull_request.body`, `github.event.comment.body`,
`github.event.discussion.body`, `github.event.*.name`.

Only flag this for values that can be set by an untrusted external contributor
(typically anything under `github.event`). Values like `github.sha` or
`github.repository` are controlled by GitHub and are safe to interpolate.

Reference: [GitHub Security Lab — Untrusted input](https://securitylab.github.com/research/github-actions-untrusted-input/)

---

### 5.2 `pull_request_target` with untrusted code checkout — ❌ always flag if present

`pull_request_target` runs in the context of the **base branch** and has access to
secrets and write permissions. If the same workflow also checks out the PR contributor's
code (head ref) and executes it — e.g., via `npm install`, `npm test`, a `Makefile`, or
any script from the checked-out tree — an attacker can exfiltrate secrets or gain write
access to the repository.

**Vulnerable pattern:**
```yaml
on: pull_request_target
jobs:
  test:
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}  # attacker-controlled code
      - run: npm install && npm test                       # runs attacker code with secrets in scope
```

This is safe only when:
- No checkout of the PR head is performed, **or**
- The checkout is strictly isolated (separate job, no secrets, no write token)

Reference: [GitHub Security Lab — Preventing pwn requests](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/)

---

### 5.3 Unpinned third-party actions — ⚠️ flag for new additions only

Using a mutable version tag (e.g., `@v2`, `@main`) for a **third-party** action means
any future push to that tag in the upstream repo silently changes the code running in
your pipeline — including potentially stealing secrets or modifying artifacts.

Flag when a PR **introduces a new `uses:` reference** to an action outside `nsbno/` that
is pinned to a floating tag rather than a full commit SHA:

```yaml
# Flag — mutable tag for an external action
- uses: some-org/some-action@v2

# Preferred — pinned to a specific commit SHA
- uses: some-org/some-action@abc1234def  # vX.Y.Z
```

**Do not flag:**
- Any `uses: nsbno/platform-actions/...@v2` — the `@v2` floating tag strategy for
  internal actions is an intentional design decision documented in `README.md`.
- Third-party actions already present in the codebase before this PR — their acceptance
  was a prior decision; only flag what is new in the diff.

Reference: [Security hardening — Using third-party actions](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-third-party-actions)

---

### 5.4 Overly broad `GITHUB_TOKEN` permissions — ⚠️ flag only when clearly excessive

`permissions: write-all` or an unnecessary `contents: write` / `id-token: write`
increases the blast radius if the workflow is compromised. Flag only when:
- The declared permission is broader than what the job's steps actually require, **and**
- You can point to the specific steps that need fewer or no permissions.

Do not flag `id-token: write` in deployment workflows — it is required for OIDC-based
AWS authentication, which is the standard pattern here.

Reference: [Security hardening — GITHUB_TOKEN permissions](https://docs.github.com/en/actions/security-guides/automatic-token-authentication#modifying-the-permissions-for-the-github_token)

---

### 5.5 Secrets interpolated into command-line arguments — ⚠️ flag when visible

Referencing a secret directly in a command-line argument (not an env var) causes the
value to appear in the process list and in workflow logs before masking takes effect.

```yaml
# Flag — secret value appears in process arguments
- run: curl -H "Authorization: Bearer ${{ secrets.API_TOKEN }}" https://example.com

# Safe — value is in the environment, not the command line
- env:
    API_TOKEN: ${{ secrets.API_TOKEN }}
  run: curl -H "Authorization: Bearer $API_TOKEN" https://example.com
```

Do not flag `secrets:` inputs declared on `workflow_call` or `jobs.<id>.secrets` blocks
— those are declarations, not exposures.

---

### What not to flag

To keep reviews signal-only, do **not** raise security comments for:
- Patterns already present throughout the existing codebase (accepted prior decisions)
- `secrets: inherit` on internal reusable workflow calls (standard pattern here)
- General statements like "secrets should be protected" without a specific leaked value
- Any risk that requires the attacker to already have repository write access

---

## 6. Naming conventions

New files must follow the established naming patterns:

| Category | Pattern |
|---|---|
| Build | `build.<language>.yml` |
| Test | `test.<language>.yml` |
| Lint | `lint.<tool>.yml` |
| Package | `package.<target>.yml` |
| Deploy (full scope) | `deployment.<scope>.yml` |
| Deploy (preview) | `deployment.preview*.yml` |
| Deploy (comment-triggered) | `deployment.<scope>.on-comment.yml` |
| Helpers | `helpers.<category>.yml` or `helpers.<category>.<subcategory>.yml` |

Composite actions must be placed under
`.github/actions/<category>/<descriptive-name>/action.yml`.

---

## 8. Review output format

Structure feedback as:

**Changed files:** list each changed file

**For each file:**
- What changed (one sentence)
- Validation result: ✅ Valid / ⚠️ Warning / ❌ Error
- Issues found with the specific input name, field, or line number and the reason

**Overall verdict:** Valid / Issues found

Keep findings concise. If everything is valid, a brief summary is better than a long one.

---

## 8. Official reference URLs

Use these when verifying syntax rather than relying on memory:

- Workflow syntax: `https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions`
- Action metadata syntax: `https://docs.github.com/en/actions/creating-actions/metadata-syntax-for-github-actions`
- Expressions: `https://docs.github.com/en/actions/learn-github-actions/expressions`
- Triggering events: `https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows`
