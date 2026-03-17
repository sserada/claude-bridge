# claude-bridge

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash%204.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Encryption: age](https://img.shields.io/badge/Encryption-age-orange.svg)](https://github.com/FiloSottile/age)

> Claude Code の会話履歴・設定をマシン間で安全に同期する CLI ツール

**[English](README.md)**

`claude-bridge` は `~/.claude/` ディレクトリを [age](https://github.com/FiloSottile/age) で暗号化し、GitHub の Private リポジトリに保存します。Git ライクなインターフェース（`push` / `pull` / `status`）で簡単に同期できます。

```
[マシン A]                     [GitHub Private Repo]              [マシン B]
~/.claude/ → 暗号化 → push → encrypted/ branch → pull → 復号 → ~/.claude/
```

## 特徴

- **Git ライク** — `push` / `pull` / `status` / `diff` のシンプルな CLI
- **暗号化ファースト** — ローカルで暗号化してから push、復号は pull 時のみ
- **差分同期** — 変更ファイルのみ暗号化・転送（SHA-256 マニフェスト）
- **ゼロコンフィグ** — `init` 一発で使い始められる
- **ゼロコスト** — GitHub Private リポをストレージに利用
- **クロスマシン対応** — `map` でマシン間のパスを変換
- **選択的同期** — `--project` で特定プロジェクトのみ同期
- **自動同期** — `auto on` で cron による定期同期

## クイックスタート

### 1台目（初回セットアップ）

```bash
# 1. GitHub でこのテンプレートから Private リポを作成
#    "Use this template" → Private に設定

# 2. クローン
git clone git@github.com:<you>/my-claude-sync.git
cd my-claude-sync

# 3. インストール & 初期化
./install.sh
claude-bridge init
# 暗号化キーペアが自動生成される

# 4. 初回 push
claude-bridge push
```

### 2台目以降

まず **1台目** で identity（秘密鍵）を表示してコピー:

```bash
cat ~/.claude-bridge/identity.txt
```

次に **2台目** で:

```bash
# 1. 同じリポをクローン
git clone git@github.com:<you>/my-claude-sync.git
cd my-claude-sync

# 2. インストール
./install.sh

# 3. 初期化 — プロンプトが出たら1台目の identity をペースト
claude-bridge init

# 4. パスが異なる場合はマッピング追加
claude-bridge map /home/user/projects/app /Users/user/dev/app
```

## 使い方

```bash
# 基本の同期
claude-bridge push                        # 暗号化して push
claude-bridge pull                        # pull して復号
claude-bridge status                      # 同期状態を表示
claude-bridge diff                        # push 前に変更をプレビュー
claude-bridge diff --content              # テキスト差分を表示

# 選択的同期
claude-bridge push --project myapp        # 特定プロジェクトのみ push
claude-bridge pull --project myapp        # 特定プロジェクトのみ pull
claude-bridge projects                    # プロジェクト一覧

# クロスマシンパス
claude-bridge map <src> <dst>             # パスマッピング追加
claude-bridge map --list                  # マッピング一覧
claude-bridge map --remove <src>          # マッピング削除

# 自動同期
claude-bridge auto on 30m                 # cron 有効化（30分ごと）
claude-bridge auto off                    # cron 無効化
claude-bridge auto status                 # cron 状態表示

# 設定
claude-bridge config                      # 設定一覧
claude-bridge config set KEY VALUE        # 設定変更
claude-bridge config get KEY              # 設定取得

# リセット
claude-bridge reset                       # 初期化（確認あり）
claude-bridge reset --force               # 確認なしで初期化
```

## 同期対象

| 対象 | パス | デフォルト |
|------|------|-----------|
| プロジェクト会話 | `projects/` | 有効 |
| コマンド履歴 | `history.jsonl` | 有効 |
| グローバル CLAUDE.md | `CLAUDE.md` | 有効 |
| 設定ファイル | `settings.json` | 有効 |
| カスタムエージェント | `agents/` | 無効 |
| カスタムスキル | `skills/` | 無効 |
| プラグイン | `plugins/` | 無効 |
| ルール | `rules/` | 無効 |

同期対象は `~/.claude-bridge/sync.conf` で設定。

## セキュリティ

- [age](https://github.com/FiloSottile/age) による鍵ペアベースの暗号化
- 暗号化済みデータのみがリモートに送信される
- Identity（秘密鍵）は `~/.claude-bridge/identity.txt` にローカル保存（`chmod 600`）
- 2台目以降のセットアップ時は、1台目から identity ファイルをコピー
- リポジトリは **Private** に設定すること（暗号化は二重防御）

## 動作要件

- Bash 4.0+
- git
- [age](https://github.com/FiloSottile/age)（`install.sh` で自動インストール）
- jq（推奨、JSON 処理用）

## ライセンス

[MIT](LICENSE)
