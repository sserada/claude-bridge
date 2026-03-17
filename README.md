# claude-bridge

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash%204.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Encryption: age](https://img.shields.io/badge/Encryption-age-orange.svg)](https://github.com/FiloSottile/age)

> Sync your Claude Code conversations and settings across machines — securely.

**[日本語はこちら / Japanese](README-ja.md)**

`claude-bridge` encrypts your `~/.claude/` directory with [age](https://github.com/FiloSottile/age) and stores it in a private Git repository. Simple git-like interface: `push`, `pull`, `status`.

```
[Machine A]                    [GitHub Private Repo]              [Machine B]
~/.claude/ → encrypt → push → encrypted/ branch → pull → decrypt → ~/.claude/
```

## Features

- **Git-like workflow** — `push` / `pull` / `status` / `diff`
- **Encryption first** — All data encrypted locally with [age](https://github.com/FiloSottile/age) before pushing
- **Differential sync** — Only changed files are encrypted and transferred (SHA-256 manifest)
- **Zero config** — `init` once, sync everywhere
- **Zero cost** — Uses your own GitHub private repo as storage
- **Cross-machine paths** — Remap project paths between machines with `map`
- **Selective sync** — Push/pull specific projects with `--project`
- **Auto-sync** — Set up periodic sync via cron with `auto on`

## Quick Start

### First Machine

```bash
# 1. Create a private repo from this template on GitHub
#    Click "Use this template" → set to Private

# 2. Clone your private repo
git clone git@github.com:<you>/my-claude-sync.git
cd my-claude-sync

# 3. Install and initialize
./install.sh
claude-bridge init
# Generates encryption key pair

# 4. Push your data
claude-bridge push
```

### Additional Machines

First, on your **first machine**, copy the identity (private key):

```bash
cat ~/.claude-bridge/identity.txt
```

Then, on the **new machine**:

```bash
# 1. Clone the same repo
git clone git@github.com:<you>/my-claude-sync.git
cd my-claude-sync

# 2. Install
./install.sh

# 3. Initialize — when prompted, paste the identity from your first machine
claude-bridge init

# 4. Map paths if they differ between machines
claude-bridge map /home/user/projects/app /Users/user/dev/app
```

## Usage

```bash
# Core sync
claude-bridge push                        # Encrypt and push changes
claude-bridge pull                        # Pull and decrypt changes
claude-bridge status                      # Show sync status
claude-bridge diff                        # Preview changes before push
claude-bridge diff --content              # Show text diffs

# Selective sync
claude-bridge push --project myapp        # Push only one project
claude-bridge pull --project myapp        # Pull only one project
claude-bridge projects                    # List all projects

# Cross-machine paths
claude-bridge map <src> <dst>             # Add path mapping
claude-bridge map --list                  # Show mappings
claude-bridge map --remove <src>          # Remove mapping

# Auto-sync
claude-bridge auto on 30m                 # Enable cron (every 30 min)
claude-bridge auto off                    # Disable cron
claude-bridge auto status                 # Show cron status

# Configuration
claude-bridge config                      # Show all settings
claude-bridge config set KEY VALUE        # Update a setting
claude-bridge config get KEY              # Read a setting
```

## What Gets Synced

| Target | Path | Default |
|--------|------|---------|
| Project conversations | `projects/` | Yes |
| Command history | `history.jsonl` | Yes |
| Global CLAUDE.md | `CLAUDE.md` | Yes |
| Settings | `settings.json` | Yes |
| Custom agents | `agents/` | No |
| Custom skills | `skills/` | No |
| Plugins | `plugins/` | No |
| Rules | `rules/` | No |

Configure sync targets in `~/.claude-bridge/sync.conf`.

## Security

- Files are encrypted with [age](https://github.com/FiloSottile/age) using a generated key pair
- Only encrypted data is pushed to the remote repository
- Identity (private key) is stored locally at `~/.claude-bridge/identity.txt` (mode `600`)
- To set up additional machines, copy the identity file from your first machine
- The repository should be **private** — encryption is a second layer of defense

## Requirements

- Bash 4.0+
- git
- [age](https://github.com/FiloSottile/age) (auto-installed by `install.sh`)
- jq (recommended, for JSON processing)

## License

[MIT](LICENSE)
