# GitHub Actions Validation Workflow

## 1. Identify what changed

Run `git diff HEAD` (or `git diff origin/main` for a full branch diff) to list changed files. Focus only on:

- `.github/workflows/*.yml` — reusable or caller workflows
- `.github/actions/**/action.yml` — composite or Docker actions

Read the full diff for each changed file.

---

## 2. Understand the change type

Determine what was changed for each file:

| Change | What to validate |
|---|---|
| New input added to `workflow_call` or `action.yml` | Input syntax (see §3), backward compatibility (see §5) |
| Input passed in `with:` to an action or called workflow | Input declared in the target definition (see §4) |
| New job or step added | Actions used exist; inputs passed are accepted; check for security patterns (see §7) |
| Expression or context reference changed | Syntax is valid (see §6); check for script injection (see §7.1) |
| New `uses:` reference to a third-party action | Check pin strategy (see §7.3) |
| `on:` trigger added or changed | Check for `pull_request_target` risk (see §7.2) |

---

## 3. Validate input definitions

When an input is added to `on.workflow_call.inputs` or to a composite action's `inputs:` block, check:

**For `workflow_call` inputs** ([official syntax](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#onworkflow_callinputs)):
- `type` is required. Must be one of: `boolean`, `number`, `string`
- `required` is optional boolean
- `default` is optional. If `required: false` and no default, the value is `false`/`0`/`""` depending on type
- `description` is optional

**For composite action inputs** ([official syntax](https://docs.github.com/en/actions/creating-actions/metadata-syntax-for-github-actions#inputs)):
- `description` is required
- `required` is optional boolean (default: `false`)
- `default` is optional string

Use WebFetch on the official docs URLs above to confirm any syntax you are uncertain about. Do not guess.

---

## 4. Validate inputs passed to actions and called workflows

When a workflow step uses `with:` to pass inputs to an action, or a job uses `with:` to pass inputs to a reusable workflow:

1. **Find the target definition.** For local actions, read `.github/actions/<name>/action.yml`. For reusable workflows in this repo, read the workflow file. For external actions/workflows, use the version tag in `uses:` to fetch from GitHub if necessary.
2. **Check every key in `with:`** is declared as an input in the target definition.
3. **Check that required inputs are not missing.** Any input marked `required: true` (or `required: true` in a `workflow_call` input with no `default`) must be supplied by every caller.
4. **Extra inputs passed to a called workflow are an error** — GitHub will reject the run. Extra inputs passed to a composite action are silently ignored but worth flagging.

---

## 5. Check backward compatibility

An optional input with a default value is backward compatible: existing callers that do not pass the new input will receive the default.

A required input with no default is a breaking change for any existing caller.

To find callers within this repo:
```bash
grep -r "uses:.*<workflow-filename>" .github/ --include="*.yml"
```

Callers in other repos cannot be found from this repo — note this limitation in your report.

---

## 6. Expression syntax

When checking `${{ ... }}` expressions:

- Context references like `inputs.foo`, `secrets.BAR`, `github.sha` are valid
- Logical expressions: `||`, `&&`
- Function calls: `startsWith()`, `contains()`, `format()`, etc.
- `${{ inputs.pnpm-version }}` passes an input from one level to the next — valid as long as the input is declared at the receiving level

Use WebFetch on `https://docs.github.com/en/actions/learn-github-actions/expressions` if you need to verify a specific expression function or operator.

---

## 7. Security checks

> **False-positive policy.** Only report a security finding when you can describe a
> concrete, realistic exploit path. Do not report theoretical risks, vague concerns, or
> patterns already established throughout the codebase. One missed real issue is better
> than noise that trains reviewers to ignore comments.
>
> Canonical reference — use WebFetch to read in full before reporting any security issue:
> `https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions`

### 7.1 Script injection — ❌ always flag if present

Embedding a user-controlled event expression directly inside a `run:` step or an
`actions/github-script` body lets an attacker inject arbitrary shell or JavaScript by
crafting an issue title, PR body, branch name, or comment.

**Vulnerable:**
```yaml
- run: echo "Branch is ${{ github.head_ref }}"
- run: echo "${{ github.event.issue.title }}"
```

**Safe — assign to an env var, then reference via shell variable:**
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

Values set by GitHub itself — `github.sha`, `github.repository`, `github.run_id` — are
safe to interpolate and should not be flagged.

Reference (use WebFetch): `https://securitylab.github.com/research/github-actions-untrusted-input/`

---

### 7.2 `pull_request_target` with untrusted code checkout — ❌ always flag if present

`pull_request_target` runs in the base-branch context and has access to secrets and write
permissions. If the same workflow also checks out the PR contributor's code and then
executes it (e.g. `npm install`, `npm test`, any script from the checked-out tree), an
attacker can exfiltrate secrets or gain write access to the repository.

All three conditions must be present to flag this:
1. Trigger is `pull_request_target`
2. A checkout of the PR head ref is performed (`ref: ${{ github.event.pull_request.head.sha }}` or `ref: refs/pull/.../head`)
3. Code from the checked-out tree is executed in the same job

Reference (use WebFetch): `https://securitylab.github.com/research/github-actions-preventing-pwn-requests/`

---

### 7.3 Unpinned third-party actions — ⚠️ flag for new additions only

A mutable version tag (`@v2`, `@main`) on a **third-party** action means any future push
to that tag silently changes the code running in the pipeline, potentially stealing
secrets or tampering with artifacts.

Flag when a PR **introduces** a new `uses:` reference outside `nsbno/` that is pinned to
a floating tag rather than a full commit SHA.

**Do not flag:**
- Any `uses: nsbno/platform-actions/...@v2` — the floating `@v2` strategy for internal
  actions is an intentional design decision documented in `README.md`.
- Third-party actions already present in the codebase before this PR — their acceptance
  was a prior decision; only flag what is new in the diff.

Reference: `https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-third-party-actions`

---

### 7.4 Overly broad `GITHUB_TOKEN` permissions — ⚠️ flag only when clearly excessive

Flag `permissions: write-all` or a specific permission that is broader than what the
job's steps actually require. You must point to the specific steps that justify the
concern — do not flag permissions speculatively.

Do not flag `id-token: write` in deployment workflows: it is required for OIDC-based AWS
authentication, which is the standard pattern in this project.

---

### 7.5 Secrets interpolated into command-line arguments — ⚠️ flag when visible

A secret referenced directly in a command-line argument appears in the process list and
workflow logs before GitHub's masking takes effect.

```yaml
# Flag — secret value appears in process arguments
- run: curl -H "Authorization: Bearer ${{ secrets.API_TOKEN }}" https://example.com

# Safe — value is in the environment, not in the command
- env:
    API_TOKEN: ${{ secrets.API_TOKEN }}
  run: curl -H "Authorization: Bearer $API_TOKEN" https://example.com
```

Do not flag `secrets:` inputs declared on `workflow_call` or `jobs.<id>.secrets` — those
are declarations, not exposures.

---

### What not to flag

- Patterns already used throughout the existing codebase (accepted decisions)
- `secrets: inherit` on internal reusable workflow calls (standard pattern here)
- Vague statements like "secrets should be protected" without a specific leaked value
- Any risk that requires the attacker to already have repository write access

---

## 8. Report findings

Structure your report as:

**Changed files:** list each file  
**For each file:**
- What changed (one line)
- Validation result: ✅ Valid / ⚠️ Warning / ❌ Error
- Any issues found, with the specific field/line and reason
- Affected callers (if any inputs became required or were removed)

**Overall verdict:** Valid / Issues found

Keep it concise. If everything is valid, a short summary is better than a long one.

---

## Official reference URLs

Always prefer fetching from these sources rather than relying on memory:

- Workflow syntax: `https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions`
- Action metadata syntax: `https://docs.github.com/en/actions/creating-actions/metadata-syntax-for-github-actions`
- Expressions: `https://docs.github.com/en/actions/learn-github-actions/expressions`
- Security hardening: `https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions`
- Script injection research: `https://securitylab.github.com/research/github-actions-untrusted-input/`
- `pull_request_target` risk: `https://securitylab.github.com/research/github-actions-preventing-pwn-requests/`
