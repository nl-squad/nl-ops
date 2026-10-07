# 🚢 nl-ops

Tools for managing NL CoD2 servers: the `mynl` CLI and shared GitHub Actions workflows.

Both read `project-definition.json` from the project directory; start from [sample.project-definition.json](sample.project-definition.json).

# 🌱 mynl CLI

## Commands

- `connect` - open an ssh session on the machine
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

## Requirements

bash, jq, rsync, ssh, nc, perl, git and zip/unzip.

## Installation

Clone this repository and create the link and alias:

```sh
sudo ln -s $(pwd)/mynl.sh /usr/local/bin/mynl.sh
alias mynl='mynl.sh'
```

# 🦩 Shared workflows

Reusable workflows in [.github/workflows](.github/workflows):

- deploy - put files on the remote machine
- restart - start or restart CoD2 server
- stop - stop CoD2 server
- save-logs - print logs of the running and the last crashed container

Use them from another repository:

```yaml
jobs:
  deploy:
    uses: nl-squad/nl-ops/.github/workflows/deploy.yml@main
    with:
      profile: default
      branch: main
    secrets: inherit
```

# 🔗 Integrated servers

- [nl-cod2-library](https://github.com/nl-squad/nl-cod2-library)
- [nl-cod2-zom-scripts](https://github.com/nl-squad/nl-cod2-zom-scripts) (private)
- [nl-cod2-zom-iwds](https://github.com/nl-squad/nl-cod2-zom-iwds)
