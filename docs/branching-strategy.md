# Branching strategy

Trunk-based, with short-lived branches and per-solution release tags.

```
main ──●────●────●──────●──────────●───▶
        \       /        \        /
         export/CoreCustomizations/123   (PR, reviewed, squash-merged)
                          tag CoreCustomizations/v1.4.0 ──▶ TEST ──▶ PROD
```

## Rules

- **`main` is always releasable.** Every commit on it has been packed and run
  through solution checker.
- **Changes come from DEV through the export workflow.** It creates
  `export/<Solution>/<run id>`; nobody needs to export by hand or commit zips.
- **Small manual edits are fine on the export branch**, for example filling in
  deployment settings or reverting an accidental change to a component that
  did not belong in this PR. Larger edits belong in DEV, otherwise the next
  export overwrites them.
- **Squash merge export PRs.** The unpacked XML diff is the history; one commit
  per export keeps `git log -- solutions/<Name>` readable.
- **Release by tagging `main`** with `<Solution>/v<major>.<minor>.<build>`.
  The tag sets the version that is stamped into the managed package.

## Why not a branch per environment

A `test` and a `prod` branch look tidy, but they drift: hotfixes get applied to
one and not the other, and merges between them become the real release
process. Here the environments are GitHub environments, the promoted thing is
an immutable build artifact, and the only branch that matters is `main`.

## Several makers in one DEV

Dataverse has no branches. If two people work in the same DEV environment,
whoever exports next takes the other person's in-progress work with them.
Options, from cheapest to most robust:

1. Agree on who exports, and export often (small PRs are easy to review).
2. Split the work into separate solutions with their own export cadence.
3. Give each developer their own DEV environment (developer plan or managed
   environments) and treat a shared environment as the integration point.

## Versioning

| Part     | Changed by                                  |
|----------|---------------------------------------------|
| Major    | Release tag. Breaking changes for consumers (removed columns, changed APIs). |
| Minor    | Release tag. New features.                  |
| Build    | Release tag. Fixes.                         |
| Revision | CI run number on non-release builds; `0` on releases unless the tag has four parts. |

Dataverse refuses to upgrade to a lower version, so a release tag must always
be higher than what is already installed downstream. Bump locally with:

```powershell
./scripts/Set-SolutionVersion.ps1 -SolutionFolder solutions/CoreCustomizations/src -Bump Minor
```

## Hotfixes

Fix in DEV, export, merge, tag the next build number (`v1.4.1`). The pipeline
is fast enough that a separate hotfix path is rarely worth the complexity. If
DEV already contains unreleased work that must not ship:

1. Branch from the last release tag: `git switch -c hotfix/1.4.1 CoreCustomizations/v1.4.0`.
2. Apply the fix to the unpacked source on that branch (or export from a
   separate environment that has the released version plus the fix).
3. Tag the branch head `CoreCustomizations/v1.4.1` and push the tag. Tag
   pushes are allowed by the environment rules regardless of branch.
4. Bring the same fix into DEV, so the next export from DEV does not undo it.
