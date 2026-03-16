# claude-bridge

Sync your Claude Code conversations and settings across machines — securely.

`claude-bridge` encrypts your `~/.claude/` directory with [age](https://github.com/FiloSottile/age) and stores it in a private Git repository. Simple git-like interface: `push`, `pull`, `status`.

## Features

- **Git-like workflow** — `claude-bridge push` / `pull` / `status`
- **Encryption first** — All data is encrypted locally before pushing (age + passphrase)
- **Differential sync** — Only changed files are encrypted and transferred
- **Zero config** — `init` once, sync everywhere
- **Zero cost** — Uses your own GitHub private repo as storage
- **Cross-machine paths** — Remap project paths between machines

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
# Enter a passphrase (remember it for other machines)
```

### Additional Machines

```bash
# 1. Clone the same repo
git clone git@github.com:<you>/my-claude-sync.git
cd my-claude-sync

# 2. Install and initialize
./install.sh
claude-bridge init
# Enter the SAME passphrase

# 3. Map paths if they differ between machines
claude-bridge map /home/user/projects/app /Users/user/dev/app
```

## Usage

```bash
# Push local changes (encrypt → commit → push)
claude-bridge push

# Pull remote changes (pull → decrypt → restore)
claude-bridge pull

# Check sync status
claude-bridge status

# Map paths between machines
claude-bridge map <source_path> <dest_path>

# View/update config
claude-bridge config
claude-bridge config set MACHINE_NAME my-laptop
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

- Files are encrypted with [age](https://github.com/FiloSottile/age) using a passphrase you choose
- Only encrypted data is pushed to the remote repository
- Passphrase is stored locally at `~/.claude-bridge/passphrase` (mode `600`)
- The repository should be **private** — encryption is a second layer of defense

## Requirements

- Bash 4.0+
- git
- [age](https://github.com/FiloSottile/age) (auto-installed by `install.sh`)
- jq (optional, for JSON processing)

## License

MIT
