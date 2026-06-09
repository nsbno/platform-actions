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
| New job or step added | Actions used exist; inputs passed are accepted |
| Expression or context reference changed | Syntax is valid (see §6) |

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

## 7. Report findings

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
- Events that trigger workflows: `https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows`
