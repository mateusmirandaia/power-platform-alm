# Setup guide

This walks through everything that has to exist outside the repository before
the workflows can run: an app registration, an application user in each
Dataverse environment, and the GitHub environments that hold URLs, secrets and
approval rules.

Expect about an hour the first time. Most of it is waiting for admin consent
and for application users to show up in the Power Platform admin center.

## 1. Environments

The pipeline assumes three Dataverse environments:

| Role | Example URL                                 | Solutions are...       |
|------|---------------------------------------------|------------------------|
| DEV  | `https://yourorg-dev.crm.dynamics.com`      | unmanaged, edited here |
| TEST | `https://yourorg-test.crm.dynamics.com`     | managed, imported only |
| PROD | `https://yourorg.crm.dynamics.com`          | managed, imported only |

TEST and PROD should never be customized by hand. If someone needs to change
something there, the change goes into DEV and follows the pipeline.

## 2. App registration

Create one app registration per trust boundary. A common split is one for
DEV + TEST and a separate one for PROD, so a leaked non-production credential
cannot touch production.

1. Microsoft Entra admin center, **App registrations**, **New registration**.
   Single tenant, no redirect URI.
2. Note the **Application (client) ID** and **Directory (tenant) ID**.
3. **API permissions**: no Microsoft Graph permissions are needed. Dataverse
   access is granted through the application user in the next step, not
   through API permissions on the app.
4. Choose an authentication method (both are supported by the workflows):

### Option A: OIDC / workload identity federation (recommended)

No secret is stored anywhere. GitHub issues a short-lived token per job and
Entra exchanges it for an access token.

**Certificates & secrets**, **Federated credentials**, **Add credential**,
scenario *GitHub Actions deploying Azure resources*. Add one credential per
subject the workflows use:

| Used by                                   | Entity type    | Value                    | Resulting subject                                |
|-------------------------------------------|----------------|--------------------------|--------------------------------------------------|
| Export workflow                           | Environment    | `dev`                    | `repo:<owner>/<repo>:environment:dev`            |
| Release to TEST                           | Environment    | `test`                   | `repo:<owner>/<repo>:environment:test`           |
| Release to PROD (on the PROD app)         | Environment    | `prod`                   | `repo:<owner>/<repo>:environment:prod`           |
| Solution checker on pull requests         | Pull request   |                          | `repo:<owner>/<repo>:pull_request`               |
| Solution checker on pushes to `main`      | Branch         | `main`                   | `repo:<owner>/<repo>:ref:refs/heads/main`        |

Issuer `https://token.actions.githubusercontent.com`, audience
`api://AzureADTokenExchange` (the defaults).

Subjects are matched exactly. If you rename an environment or a branch, the
federated credential has to change with it; the error you get otherwise is
`AADSTS70021: No matching federated identity record found`.

### Option B: client secret

**Certificates & secrets**, **New client secret**. Store the value as the
`PP_CLIENT_SECRET` secret (see section 4). Put a reminder in your calendar for
the expiry date; an expired secret is the most common reason a release that
worked last month fails today.

The workflows pick the method automatically: if `PP_CLIENT_SECRET` is empty,
the Power Platform actions use federation.

## 3. Application users and security roles

The service principal needs an application user in every environment it talks
to.

Power Platform admin center, environment, **Settings**, **Users + permissions**,
**Application users**, **New app user**, select the app registration and a
business unit, then assign roles:

| Environment | Role                     | Why                                                       |
|-------------|--------------------------|-----------------------------------------------------------|
| DEV         | System Customizer        | Enough to publish and export solutions.                   |
| TEST        | System Administrator     | Importing managed solutions with plug-ins, flows and      |
| PROD        | System Administrator     | connection references needs more than System Customizer.  |

The same can be scripted with pac, which is handy when environments are
recreated often:

```bash
pac admin assign-user \
  --environment https://yourorg-test.crm.dynamics.com \
  --user 00000000-0000-0000-0000-000000000000 \
  --role "System Administrator" \
  --application-user
```

Connections referenced by the deployment settings must be **shared with the
application user** (or owned by it). Otherwise the import succeeds but the
flows that use them stay off.

## 4. GitHub configuration

### Environments

**Settings**, **Environments**:

| Environment | Protection rules                                                                                  |
|-------------|---------------------------------------------------------------------------------------------------|
| `dev`       | None, or restrict to the people allowed to trigger exports.                                       |
| `test`      | Deployment branches and tags: `main` and tag pattern `*/v*`.                                      |
| `prod`      | Same branch/tag rule, **required reviewers**, and *prevent self-review* so the person who tagged the release cannot approve it. |

### Variables and secrets

Repository-level values are shared by every job; environment-level values
override them for jobs that run in that environment. That is how PROD can use
its own app registration without any change to the workflows.

| Name                         | Kind     | Scope                         | Required | Example / notes                                         |
|------------------------------|----------|-------------------------------|----------|---------------------------------------------------------|
| `PP_TENANT_ID`               | Variable | Repository                    | Yes      | `00000000-0000-0000-0000-000000000000`                  |
| `PP_APP_ID`                  | Variable | Repository (override in `prod`) | Yes    | `00000000-0000-0000-0000-000000000000`                  |
| `PP_ENVIRONMENT_URL`         | Variable | Each environment              | Yes      | `https://yourorg-test.crm.dynamics.com`                 |
| `PP_CHECKER_ENVIRONMENT_URL` | Variable | Repository                    | Yes      | Usually DEV: `https://yourorg-dev.crm.dynamics.com`     |
| `PP_CHECKER_GEO`             | Variable | Repository                    | No       | Defaults to `UnitedStates`. Use your tenant's geo.      |
| `PP_PAC_VERSION`             | Variable | Repository                    | No       | Pin the CLI, e.g. `2.8.1`, so CI matches local tooling. |
| `PP_CLIENT_SECRET`           | Secret   | Repository or environment     | Option B | Leave unset when using OIDC.                            |
| `ALM_BOT_CLIENT_ID`          | Variable | Repository                    | No       | GitHub App used to open export PRs.                     |
| `ALM_BOT_PRIVATE_KEY`        | Secret   | Repository                    | No       | Private key of that GitHub App.                         |

A note on secrets and reusable workflows: a secret defined on a GitHub
environment wins over the one the caller passes in, because the deploy job
declares `environment:`. So a PROD-only client secret can live on the `prod`
environment and the repository secret is used everywhere else.

### Actions settings

- **Settings**, **Actions**, **General**, **Workflow permissions**: leave the
  default token read-only (every workflow asks for what it needs) and tick
  *Allow GitHub Actions to create and approve pull requests* if you are not
  using a GitHub App for exports.
- Protect `main`: require the *Build solution* and *Lint* checks and at least
  one review.

### Optional: GitHub App for export PRs

A pull request opened with `GITHUB_TOKEN` does not trigger other workflows, so
the build would not run on the export PR until someone pushes to it. Create a
GitHub App with **Contents: read & write** and **Pull requests: read & write**,
install it on this repository, and set `ALM_BOT_CLIENT_ID` and
`ALM_BOT_PRIVATE_KEY`. The export workflow uses it when present.

## 5. First run

1. Run **Export solution** with your solution's unique name and `dev`.
2. Review the PR. New environment variables and connection references show up
   in `deployment-settings/*.json` with empty values or the all-zero GUID; fill
   them in on the same branch.
3. Merge. *Build solution* packs and checks it on `main`.
4. Tag the release and push the tag:

   ```bash
   git tag CoreCustomizations/v1.0.0
   git push origin CoreCustomizations/v1.0.0
   ```

5. Watch it deploy to TEST, then approve the PROD deployment.

To get a connection ID for the settings file, open the connection in the
maker portal (**Connections**, select it) and copy the ID from the URL, or run
`pac connection list` against the target environment.
