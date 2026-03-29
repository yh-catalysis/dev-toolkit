# dev-toolkit

[English](#english) | [日本語](#日本語)

## English

Opinionated shell scripts to bootstrap, secure, and audit personal GitHub repositories.

### Features

- **`new-repo.sh`** — Create a new repo with layered templates (common + stack overlay) and GitHub security settings, all in one command
- **`secure-repo.sh`** — Idempotently apply security settings (secret scanning, push protection, branch protection, etc.) to any existing repo
- **`audit-repos.sh`** — Audit all your repos for security and configuration compliance

### Requirements

- **bash** (macOS / Linux / WSL2 — not compatible with Windows cmd or PowerShell)
- [GitHub CLI (`gh`)](https://cli.github.com/) — authenticated via `gh auth login`
- **git**

### Quick Start

```bash
git clone https://github.com/yh-catalysis/dev-toolkit.git
cd dev-toolkit

# Create a new Python project (private by default)
./bin/new-repo.sh my-tool --stack python

# Create a public JS/TS project
./bin/new-repo.sh my-app --stack js --public

# Apply security settings to an existing repo
./bin/secure-repo.sh owner/repo-name

# Audit all your public repos
./bin/audit-repos.sh --public-only
```

### Template Structure

```text
templates/
├── common/          # Shared across all repos (LICENSE, SECURITY.md, dependabot.yml, etc.)
├── python/          # Python overlay (pyproject.toml, CI, smoke test, etc.)
├── js/              # JS/TS overlay (CI, etc.)
└── dotnet/          # .NET overlay (CI, etc.)
```

Placeholders in templates are replaced automatically:

| Placeholder | Replaced with |
| --- | --- |
| `{{PROJECT_NAME}}` | Repository name |
| `{{YEAR}}` | Current year |
| `{{GITHUB_USER}}` | GitHub username |

### Design Decisions

- **No auto-commit or auto-push** — The script only writes files locally and generates a `POST_SETUP.md` checklist. You decide when to commit and push.
- **All GitHub Actions pinned by commit SHA** — Prevents tag-based supply chain attacks (e.g., force-push tag hijacking).
- **Layered templates over GitHub Template Repos** — One set of common files + per-stack overlays, easier to maintain than N template repos.

### License

[MIT](LICENSE)

---

## 日本語

個人 GitHub リポジトリの作成・セキュリティ設定・監査を標準化するシェルスクリプト集です。

### 機能

- **`new-repo.sh`** — レイヤード テンプレート（共通 + スタック別オーバーレイ）の適用と GitHub セキュリティ設定をワンコマンドで実行
- **`secure-repo.sh`** — 既存リポジトリにセキュリティ設定を冪等に適用（secret scanning, push protection, ブランチ保護など）
- **`audit-repos.sh`** — 全リポジトリのセキュリティ・設定準拠状態を監査

### 動作要件

- **bash**（macOS / Linux / WSL2。Windows cmd や PowerShell では動作しません）
- [GitHub CLI (`gh`)](https://cli.github.com/)（`gh auth login` で認証済みであること）
- **git**

### クイックスタート

```bash
git clone https://github.com/yh-catalysis/dev-toolkit.git
cd dev-toolkit

# Python プロジェクト（デフォルトはプライベート）
./bin/new-repo.sh my-tool --stack python

# JS/TS プロジェクト（パブリック）
./bin/new-repo.sh my-app --stack js --public

# 既存リポジトリにセキュリティ設定を適用
./bin/secure-repo.sh owner/repo-name

# 公開リポジトリのみ監査
./bin/audit-repos.sh --public-only
```

### テンプレート構成

```text
templates/
├── common/          # 全リポ共通（LICENSE, SECURITY.md, dependabot.yml 等）
├── python/          # Python 用オーバーレイ（pyproject.toml, CI, スモークテスト等）
├── js/              # JS/TS 用オーバーレイ（CI 等）
└── dotnet/          # .NET 用オーバーレイ（CI 等）
```

テンプレート内のプレースホルダは自動置換されます:

| プレースホルダ | 置換内容 |
| --- | --- |
| `{{PROJECT_NAME}}` | リポジトリ名 |
| `{{YEAR}}` | 作成年 |
| `{{GITHUB_USER}}` | GitHub ユーザー名 |

### 設計方針

- **自動コミット・プッシュをしない** — ファイルのローカル配置と `POST_SETUP.md` チェックリストの生成のみ。コミットとプッシュのタイミングはユーザーが決める。
- **全 GitHub Actions をコミット SHA で固定** — タグの force-push によるサプライチェーン攻撃を防止。
- **GitHub Template Repos ではなくレイヤードテンプレート** — 共通テンプレート + スタック別オーバーレイの構成で、N 個のテンプレートリポジトリを管理するより保守が容易。

### ライセンス

[MIT](LICENSE)
