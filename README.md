# 🚢 nl-ops

Tools for managing NL CoD2 servers: the `mynl` CLI and shared GitHub Actions workflows.

Both read `project-definition.json` from the project directory; start from [sample.project-definition.json](sample.project-definition.json).

# 🌱 mynl CLI

## Features

- direct connect
- deploying the local repository version
- restarting the remote server
- getting logs
- reloading the current map
- rotating the current map
- changing to any given map
- executing a remote command as RCON
- getting info and status
- creating .iwd files
- unpacking .iwd files
- release management

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
