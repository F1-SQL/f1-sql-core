# Release operations

The release workflow runs every Tuesday after the race weekend window and can
also be started with **Run workflow**. It first runs the lightweight `f1sql
detect` command. It selects the latest settled round whose cumulative source
fingerprint has not already been released, so a missed scheduled run catches
up to the newest available round.

The current workflow's validation job is deliberately non-publishing. It runs
the offline test suite and initializes an isolated workspace. SQL Server 2019
loading and SQL Server 2022 restore-forward verification are exercised by the
separate `sqlserver.yml` workflow. Scheduled runs publish automatically after
every release gate passes. Manual runs retain a double opt-in: a maintainer must
set `dry_run=false` and request `publish=true`. Both paths require the protected
`production` environment and the repository variable
`F1SQL_RELEASE_BUNDLE_READY=true`. The production build fetches the settled
Jolpica round, loads the FastF1 Race session, runs quality/reconciliation gates,
creates a SQL Server 2019 backup, restore-forward verifies it on SQL Server 2022,
and uploads `release-bundle`. Publication remains fail-closed while the
repository readiness flag is disabled.

Production candidates are season-to-date snapshots: when round `N` is ready,
the build fetches and normalizes every settled round from round 1 through `N`.
The resulting SQL Server backup therefore grows with each release instead of
containing only the newest race.

For a dry run, leave `dry_run=true` (the default) and `publish=false`. The
publish job explicitly rejects dry-run dispatches even if both the environment
variable and the publish input are accidentally enabled.

On failure, the detector and validation jobs upload diagnostic artifacts when
available. Rerunning a workflow is safe because release packaging refuses to
replace an existing version and the detector compares source fingerprints.

Required production setup before enabling publication:

1. Configure a protected `production` environment with required reviewers and
   restrict deployment branches/tags.
2. Keep repository-level `GITHUB_TOKEN` permissions read-only; the publish job
   alone requests `contents: write`.
3. Add SQL Server 2019 and 2022 integration runners. The integration workflow
   generates disposable SA passwords for each container; no database password
   is stored in repository or environment secrets.
4. Store the monorepo SHA, `database/schema/v2` path, and source versions in the
   run manifest.
5. Enable `F1SQL_RELEASE_BUNDLE_READY` only after the build job produces and
   verifies a complete release bundle.
6. Add an approval gate after quality, backup, and restore verification.
