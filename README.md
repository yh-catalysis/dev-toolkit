# dev-toolkit

[English](#english) | [日本語](#日本語)

## English

Opinionated shell scripts to bootstrap, secure, and audit personal GitHub repositories.

### Features

- **`new-repo.sh`** — Create a new repo with layered templates (common + stack overlay) and GitHub security settings, all in one command
- **`secure-repo.sh`** — Idempotently apply security settings (secret scanning, push protection, branch protection, etc.) to any existing repo
- **`audit-repos.sh`** — Audit your repos for security and configuration compliance (public and/or private, owned or shared with you)

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

# Audit every repo you own (public and private)
./bin/audit-repos.sh
```

### Choosing which repos `audit-repos.sh` checks

With no options, `audit-repos.sh` checks every repository you own, both public and private. Two options change that:

| Option | Values | Default | What it means |
| --- | --- | --- | --- |
| `--visibility` | `all`, `public`, `private` | `all` | Include public repos, private repos, or both |
| `--affiliation` | `owner`, `collaborator`, `organization_member` (comma-separated), or `all` | `owner` | Your relationship to the repo (GitHub calls this "affiliation") |

The `--affiliation` values:

- `owner` — repos under your own account
- `collaborator` — someone else's repos that you were invited to
- `organization_member` — repos of an organization you belong to

```bash
# Only your public repos (same as --visibility public)
./bin/audit-repos.sh --public-only

# Private repos you own or were invited to
./bin/audit-repos.sh --visibility private --affiliation owner,collaborator

# Every repo you can access
./bin/audit-repos.sh --affiliation all
```

Some checks need admin access to the repo: Dependabot alerts, Dependabot security updates, and the security features of public repos. GitHub hides these settings from people who are not admins, so on such repos (usually `collaborator` and `organization_member` ones) these checks are shown as "not checked" instead of as warnings.

`--user <username>` audits another account instead of yours. GitHub lists only the public repos that account owns, so `--user` cannot be combined with `--visibility private` / `all` or with an `--affiliation` other than `owner`.

### Template Structure

```text
templates/
├── common/          # Shared across all repos (LICENSE, SECURITY.md, renovate.json, etc.)
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
- **Renovate for dependency updates, Dependabot for alerts only** — Running both opens duplicate PRs. Dependabot alerts stay on because Renovate's `vulnerabilityAlerts` reads them to open security PRs; `dependabot.yml` and Dependabot security updates are not used.

### License

[MIT](LICENSE)

---

## 日本語

個人 GitHub リポジトリの作成・セキュリティ設定・監査を標準化するシェルスクリプト集です。

### 機能

- **`new-repo.sh`** — レイヤード テンプレート（共通 + スタック別オーバーレイ）の適用と GitHub セキュリティ設定をワンコマンドで実行
- **`secure-repo.sh`** — 既存リポジトリにセキュリティ設定を冪等に適用（secret scanning, push protection, ブランチ保護など）
- **`audit-repos.sh`** — リポジトリのセキュリティ・設定準拠状態を監査（公開・非公開や、自分の所有か招待されたものかを選べる）

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

# 自分が所有するリポジトリを、公開・非公開とも監査
./bin/audit-repos.sh
```

### `audit-repos.sh` の監査対象の選び方

オプションを付けないと、自分が所有するリポジトリを、公開・非公開の区別なくすべて監査します。対象は次の2つのオプションで変えられます。

| オプション | 値 | 既定 | 意味 |
| --- | --- | --- | --- |
| `--visibility` | `all` / `public` / `private` | `all` | 公開リポジトリと非公開リポジトリのどちらを含めるか |
| `--affiliation` | `owner` / `collaborator` / `organization_member`（カンマ区切り）、または `all` | `owner` | 自分とリポジトリの関係（GitHub の用語で affiliation） |

`--affiliation` の値の意味:

- `owner` — 自分のアカウントにあるリポジトリ
- `collaborator` — 他人のリポジトリのうち、自分が招待されたもの
- `organization_member` — 自分が所属する Organization のリポジトリ

```bash
# 公開リポジトリだけ（--visibility public と同じ）
./bin/audit-repos.sh --public-only

# 自分が所有する、または招待された非公開リポジトリ
./bin/audit-repos.sh --visibility private --affiliation owner,collaborator

# アクセスできるリポジトリすべて
./bin/audit-repos.sh --affiliation all
```

一部の確認には、リポジトリの admin 権限が要ります（Dependabot alerts、Dependabot security updates、公開リポジトリのセキュリティ機能）。GitHub はこれらの設定を admin 以外には見せません。そのため admin でないリポジトリ（多くは `collaborator` と `organization_member` のもの）では、警告にせず「not checked」と表示します。

`--user <ユーザー名>` を付けると、自分ではなく別のアカウントを監査します。GitHub が返すのはそのアカウントが所有する公開リポジトリだけなので、`--user` は `--visibility private` / `all` や、`owner` 以外の `--affiliation` とは一緒に使えません。

### テンプレート構成

```text
templates/
├── common/          # 全リポ共通（LICENSE, SECURITY.md, renovate.json 等）
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
- **依存更新は Renovate、Dependabot はアラートだけ** — 両方で更新すると PR が二重に出る。Renovate の `vulnerabilityAlerts` は Dependabot alerts を読んで脆弱性の PR を作るので、alerts は有効のままにする。`dependabot.yml` と Dependabot security updates は使わない。

### ライセンス

[MIT](LICENSE)
