# Troubleshooting

Problems roughly in the order people hit them.

## Authentication

**`AADSTS70021: No matching federated identity record found`**
The OIDC subject of the job does not match any federated credential on the
app registration. The error message contains the subject GitHub sent; compare
it with the table in [setup.md](setup.md#option-a-oidc--workload-identity-federation-recommended).
Typical causes: a job that runs under an environment (subject is
`environment:<name>`, not the branch), or a renamed environment.

**`Unable to get an access token` / `id-token` errors**
The job is missing `permissions: id-token: write`. Reusable workflows inherit
at most what the calling job grants, so both levels need it.

**`AADSTS7000215: Invalid client secret provided`**
The secret expired or the *Secret ID* was stored instead of the *Value*.

**`The user is not a member of the organization`**
The application user does not exist in that environment, or it is disabled.
See [setup.md, section 3](setup.md#3-application-users-and-security-roles).

## Export

**The PR is created but *Build solution* never runs on it**
Pull requests opened with `GITHUB_TOKEN` do not trigger workflows. Configure
the optional GitHub App, or push an empty commit to the branch.

**`GitHub Actions is not permitted to create or approve pull requests`**
Enable that option under *Settings, Actions, General*, or use the GitHub App.

**Huge diffs on every export, mostly reordered XML**
Usually a different pac version between runs, or a one-off unpack done by hand
with other options. Pin the CLI with the `PP_PAC_VERSION` variable, run one
export through the workflow, merge it, and the noise goes away.

**Canvas apps show up as binary `.msapp` diffs**
Expected. `--processCanvasApps` is deprecated in pac and removed in newer
releases, so it is not used here: source unpacked with it could not be packed
again after a CLI upgrade. Review canvas app changes in the maker portal, or
use Power Apps' own source control integration for those apps.

**A component I deleted in DEV is still in the source**
It is still in the solution. Removing a component from a solution and deleting
it from the environment are two different things in Dataverse.

## Build and solution checker

**Pack fails with `Solution package type did not match requested type`**
The source was unpacked as Unmanaged only (`<Managed>0</Managed>` in
`Other/Solution.xml`). Managed packing needs an unpack
with `solution-type: Both`, which the export workflow does. Re-export.

**Checker fails the build on a rule you consider noise**
Add an override instead of disabling the checker:

```json
[
  { "Id": "meta-remove-dup-reg", "OverrideLevel": "Medium" }
]
```

Save it as `.github/solution-checker/rule-overrides.json`; the build picks it
up automatically. Explain each override in the PR that adds it.

**Checker is skipped on a pull request**
It is a PR from a fork. Secrets are not available there, so only the pack
step runs. A maintainer can re-run the checks after pushing the branch to the
main repository.

## Deployment

**`Connection reference ... still has a placeholder ConnectionId`**
Expected on a fresh repository: `deployment-settings/*.json` ship with
all-zero GUIDs. Replace them with real connection IDs for that environment.

**Import succeeds, but flows are turned off**
The connection in the settings file is not shared with the application user,
or it belongs to a different connector than the connection reference.

**`Solution ... with version X already exists. Import a higher version.`**
The tag version is not higher than what is installed. Tag the next version.

**`Cannot start another [Import] because there is a previous [Import] running`**
Another import was still running in that environment (from a portal user or
from another pipeline). Deployments of the same solution are queued by the
workflow; imports started elsewhere are not. Re-run when the other one ends.

**Stage and upgrade takes a long time, or times out**
Large solutions with many components to delete can take well over an hour.
Raise `max-async-wait-time` in `_deploy.yml` and the job's `timeout-minutes`
together.

**A missing dependency blocks the import**
The managed solution depends on something that is not installed downstream,
typically another of your solutions or a first-party app. Deploy the
dependency first, or remove the dependency in DEV. The error lists the
component IDs; `pac solution check` shows them too.

## Local debugging

Everything the workflows do can be reproduced locally with pac:

```bash
pac auth create --environment https://yourorg-dev.crm.dynamics.com
pac solution export --name CoreCustomizations --path out/CoreCustomizations.zip
pac solution export --name CoreCustomizations --path out/CoreCustomizations_managed.zip --managed
pac solution unpack --zipfile out/CoreCustomizations.zip \
  --folder solutions/CoreCustomizations/src --packagetype Both
pac solution pack --zipfile out/CoreCustomizations_managed.zip \
  --folder solutions/CoreCustomizations/src --packagetype Managed
```
