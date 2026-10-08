# 🚢 nl-ops

Tools for managing NL CoD2 servers: the `mynl` CLI and shared GitHub Actions workflows.

Both read `project-definition.json` from the project directory; start from [sample.project-definition.json](sample.project-definition.json).

# 🌱 mynl CLI

## Commands

- `connect [command]` - open an ssh session on the machine, or run the command there
- `deploy` - pack the iwds, rsync to the server and announce the update; reload with `exec map_restart`
  - packs `iwds/<name>.iwd/<any folder>/…` into `<iwdsPath>/<name>.iwd`, only when something in the source folder is newer; delete the `.iwd` to force a repack
  - rsyncs `localDeploymentPath` with `--delete`, so list server-only files in `rsyncExclude`; anchor top-level ones, e.g. `/000empty.iwd`
- `restart` - remove the docker stack and start it again
- `stop` - print the last logs and remove the docker stack
- `logs [follow|lines]` - print or follow the server logs
- `history [index]` - print the logs of a stopped container
- `status` - print the map and players (no rcon password needed)
- `exec <command>` - run an RCON command, e.g. `exec status` or `exec map_restart`
- `release <version>` - tag the previous version, branch `version/<version>` from main, deploy to public

The `default` profile is used unless you set another one with `export PROFILE=<name>`.

Passwords for the active profile come from `RCON_PASSWORD` and `G_PASSWORD`, otherwise from `./.env` (see [.env.example](.env.example)). Set `G_PASSWORD=" "` for no password. `release` requires both env vars unset. `MYNL_SSH_KEY` overrides `connection.keyPath`. SSH host keys are pinned in [known_hosts](known_hosts).

## Requirements

bash, jq, rsync, ssh, perl, git and zip.

## Installation

Clone this repository and create the link and alias:

```sh
sudo ln -s $(pwd)/mynl.sh /usr/local/bin/mynl.sh
alias mynl='mynl.sh'
```

# 🦩 Shared workflows

Reusable workflows in [.github/workflows](.github/workflows). Each one runs `mynl.sh` from the same nl-ops commit as the workflow, in the root of the caller repository.

| Workflow | Runs | Inputs |
|---|---|---|
| deploy | `deploy`, `connect <run_after>` | `profile`, `ref` (optional), `run_after` (optional) |
| restart | `logs 500`, `history`, `restart` | `profile` |
| stop | `stop` | `profile` |
| save-logs | `logs 500`, `history` | `profile` |

Deploy caches the packed `.iwd` files with `actions/cache`, keyed by the git tree hash of `iwds/`, so unchanged iwds are not packed again.

Pass secrets with `secrets: inherit`. The `public` profile uses the `PUBLIC_` ones, every other profile the `DEV_` ones.

- `VPS_PRIVATE_KEY` - all workflows
- `DEV_RCON_PASSWORD` / `PUBLIC_RCON_PASSWORD` - deploy, restart and stop of a profile with `cod2.port`. Without it, the in-game announcement is skipped. Deploy of a profile with `cod2.cfgFile` requires it.
- `DEV_G_PASSWORD` / `PUBLIC_G_PASSWORD` - deploy of a profile with `cod2.cfgFile`; `" "` means no password

```yaml
jobs:
  deploy:
    uses: nl-squad/nl-ops/.github/workflows/deploy.yml@main
    with:
      profile: default
    secrets: inherit
```

# 🔗 Integrated servers

- [nl-cod2-library](https://github.com/nl-squad/nl-cod2-library)
- [nl-cod2-zom-scripts](https://github.com/nl-squad/nl-cod2-zom-scripts) (private)
- [nl-cod2-zom-iwds](https://github.com/nl-squad/nl-cod2-zom-iwds)
