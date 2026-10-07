# 🚢 nl-ops

Tools for managing NL CoD2 servers: the `mynl` CLI and shared GitHub Actions workflows.

Both read `project-definition.json` from the project directory; start from [sample.project-definition.json](sample.project-definition.json).

# 🌱 mynl CLI

## Commands

- `connect [command]` - open an ssh session on the machine, or run the command there
- `deploy` - rsync the local files to the server
- `restart` - remove the docker stack and start it again
- `stop` - print the last logs and remove the docker stack
- `sync` - pack, deploy, then restart the map (or the whole server if it is down)
- `logs [follow|lines]` - print or follow the server logs
- `history [index]` - print the logs of a stopped container
- `pack` / `unpack` - build `.iwd` files from `iwds/`, or unpack them there
- `getstatus`, `status`, `mapres`, `exec <command>` - query or control the server over RCON
- `release-version <version>` / `finalize-version <version>` - release management

The `default` profile is used unless you set another one with `export PROFILE=<name>`.

Passwords for the active profile come from `RCON_PASSWORD` and `G_PASSWORD`, otherwise from `./secrets` (see [secrets-example](secrets-example)). Set `G_PASSWORD=" "` for no password. `release-version` requires both env vars unset. `MYNL_SSH_KEY` overrides `connection.keyPath`. SSH host keys are pinned in [known_hosts](known_hosts).

## Requirements

bash, jq, rsync, ssh, nc, perl, git and zip/unzip.

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
| deploy | `pack` (if `iwds/` exists), `deploy`, `connect <run_after>` | `profile`, `ref` (optional, defaults to the triggering commit), `run_after` (optional command run on the server in `remoteDeploymentPath`) |
| restart | `logs 500`, `history`, `restart` | `profile` |
| stop | `stop` | `profile` |
| save-logs | `logs 500`, `history` | `profile` |

Secrets, passed with `secrets: inherit`. The `public` profile uses the `PUBLIC_` ones, every other profile the `DEV_` ones.

- `VPS_PRIVATE_KEY` - all workflows
- `DEV_RCON_PASSWORD` / `PUBLIC_RCON_PASSWORD` - deploy, restart and stop of a profile with `cod2.port`; without it the in-game announcement is skipped, and deploy of a profile with `cod2.cfgFile` fails
- `DEV_G_PASSWORD` / `PUBLIC_G_PASSWORD` - deploy of a profile with `cod2.cfgFile`; `" "` means no password

Deploy, restart and stop of the same profile in one repository wait for each other.

```yaml
jobs:
  deploy:
    uses: nl-squad/nl-ops/.github/workflows/deploy.yml@main
    with:
      profile: default
      ref: ${{ inputs.sha }}
    secrets: inherit
```

# 🔗 Integrated servers

- [nl-cod2-library](https://github.com/nl-squad/nl-cod2-library)
- [nl-cod2-zom-scripts](https://github.com/nl-squad/nl-cod2-zom-scripts) (private)
- [nl-cod2-zom-iwds](https://github.com/nl-squad/nl-cod2-zom-iwds)
