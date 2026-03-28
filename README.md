# dev-toolkit

個人開発リポジトリの作成・セキュリティ設定を標準化するツールキット。

## 使い方

### 新規リポジトリ作成

```bash
# Python プロジェクト（プライベート）
./bin/new-repo.sh my-tool --stack python

# JS/TS プロジェクト（パブリック）
./bin/new-repo.sh my-app --stack js --public

# スタック指定なし（共通テンプレのみ）
./bin/new-repo.sh my-notes --private
```

### 既存リポジトリにセキュリティ設定を適用

```bash
./bin/secure-repo.sh yh-catalysis/my-existing-repo
```

### 全リポジトリの監査

```bash
./bin/audit-repos.sh
```

## 構成

```
templates/
├── common/          # 全リポ共通（LICENSE, SECURITY.md, dependabot.yml 等）
├── python/          # Python 用オーバーレイ（pyproject.toml, CI 等）
└── js/              # JS/TS 用オーバーレイ（CI 等）
```

## テンプレートのカスタマイズ

`templates/` 配下のファイルを編集し、このリポにコミットしてください。
`new-repo.sh` が作成時に以下のプレースホルダを自動置換します:

- `{{PROJECT_NAME}}` → リポジトリ名
- `{{YEAR}}` → 作成年
- `{{GITHUB_USER}}` → GitHub ユーザー名

## 設計思想

- **GitHub Template Repos を使わない理由**: スタックごとにテンプレが必要になり保守が困難
- **gh CLI スクリプト駆動**: 追加ツール不要。段階的に育てられる
- **全 Actions は SHA 固定**: タグ改ざん型サプライチェーン攻撃への対策
