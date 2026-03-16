# claude-bridge

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash%204.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Encryption: age](https://img.shields.io/badge/Encryption-age-orange.svg)](https://github.com/FiloSottile/age)

> Sync your Claude Code conversations and settings across machines — securely.

**[日本語はこちら / Japanese](#japanese)**

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
# Enter a passphrase (remember it for other machines)

# 4. Push your data
claude-bridge push
```

### Additional Machines

```bash
# 1. Clone the same repo
git clone git@github.com:<you>/my-claude-sync.git
cd my-claude-sync

# 2. Install and initialize (use the SAME passphrase)
./install.sh
claude-bridge init

# 3. Map paths if they differ between machines
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

- Files are encrypted with [age](https://github.com/FiloSottile/age) using a passphrase you choose
- Only encrypted data is pushed to the remote repository
- Passphrase is stored locally at `~/.claude-bridge/passphrase` (mode `600`)
- The repository should be **private** — encryption is a second layer of defense

## Requirements

- Bash 4.0+
- git
- [age](https://github.com/FiloSottile/age) (auto-installed by `install.sh`)
- jq (recommended, for JSON processing)

## License

[MIT](LICENSE)

---

<a id="japanese"></a>

## 日本語

> Claude Code の会話履歴・設定をマシン間で安全に同期する CLI ツール

### 概要

`claude-bridge` は `~/.claude/` ディレクトリを [age](https://github.com/FiloSottile/age) で暗号化し、GitHub の Private リポジトリに保存します。Git ライクなインターフェース（`push` / `pull` / `status`）で簡単に同期できます。

### 特徴

- **Git ライク** — `push` / `pull` / `status` / `diff` のシンプルな CLI
- **暗号化ファースト** — ローカルで暗号化してから push、復号は pull 時のみ
- **差分同期** — 変更ファイルのみ暗号化・転送（SHA-256 マニフェスト）
- **ゼロコンフィグ** — `init` 一発で使い始められる
- **ゼロコスト** — GitHub Private リポをストレージに利用
- **クロスマシン対応** — `map` でマシン間のパスを変換
- **選択的同期** — `--project` で特定プロジェクトのみ同期
- **自動同期** — `auto on` で cron による定期同期

### クイックスタート

#### 1台目（初回セットアップ）

```bash
# 1. GitHub でこのテンプレートから Private リポを作成
#    "Use this template" → Private に設定

# 2. クローン
git clone git@github.com:<you>/my-claude-sync.git
cd my-claude-sync

# 3. インストール & 初期化
./install.sh
claude-bridge init
# パスフレーズを入力（他のマシンでも同じものを使用）

# 4. 初回 push
claude-bridge push
```

#### 2台目以降

```bash
# 1. 同じリポをクローン
git clone git@github.com:<you>/my-claude-sync.git
cd my-claude-sync

# 2. インストール & 初期化（同じパスフレーズを使用）
./install.sh
claude-bridge init

# 3. パスが異なる場合はマッピング追加
claude-bridge map /home/user/projects/app /Users/user/dev/app
```

### セキュリティ

- [age](https://github.com/FiloSottile/age) によるパスフレーズベースの暗号化
- 暗号化済みデータのみがリモートに送信される
- パスフレーズは `~/.claude-bridge/passphrase` にローカル保存（`chmod 600`）
- リポジトリは **Private** に設定すること（暗号化は二重防御）

### 動作要件

- Bash 4.0+
- git
- [age](https://github.com/FiloSottile/age)（`install.sh` で自動インストール）
- jq（推奨、JSON 処理用）
