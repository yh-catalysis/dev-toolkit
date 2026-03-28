#!/usr/bin/env bash
set -euo pipefail

# ─── new-repo.sh ─────────────────────────────────────────────────────────────
# 新規リポジトリを作成し、テンプレートとセキュリティ設定を適用する
# Usage: ./bin/new-repo.sh <repo-name> [--stack python|js] [--public] [--private]
# ─────────────────────────────────────────────────────────────────────────────

TOOLKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$TOOLKIT_DIR/templates"

# ─── Defaults ────────────────────────────────────────────────────────────────
VISIBILITY="private"
STACK=""
REPO_NAME=""
GITHUB_USER="$(gh api user --jq '.login' 2>/dev/null || echo '')"
YEAR="$(date +%Y)"
CLONE_DIR="${DEV_TOOLKIT_CLONE_DIR:-$HOME/projects/github/personal}"

# ─── Helpers ─────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") <repo-name> [OPTIONS]

Options:
  --stack <python|js>   Apply language-specific overlay
  --public              Create as public repository (default: private)
  --private             Create as private repository
  --clone-dir <path>    Clone destination (default: $CLONE_DIR)
  -h, --help            Show this help

Examples:
  $(basename "$0") my-tool --stack python --public
  $(basename "$0") my-app --stack js
  $(basename "$0") my-notes
EOF
  exit 0
}

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$1"; }
ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$1"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$1"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; exit 1; }

replace_placeholders() {
  local file="$1"
  if [[ -f "$file" ]] && file --mime-type "$file" | grep -q text; then
    sed -i \
      -e "s/{{PROJECT_NAME}}/$REPO_NAME/g" \
      -e "s/{{YEAR}}/$YEAR/g" \
      -e "s/{{GITHUB_USER}}/$GITHUB_USER/g" \
      "$file"
  fi
}

# ─── Parse arguments ────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)     STACK="$2"; shift 2 ;;
    --public)    VISIBILITY="public"; shift ;;
    --private)   VISIBILITY="private"; shift ;;
    --clone-dir) CLONE_DIR="$2"; shift 2 ;;
    -h|--help)   usage ;;
    -*)          error "Unknown option: $1" ;;
    *)           REPO_NAME="$1"; shift ;;
  esac
done

[[ -z "$REPO_NAME" ]] && error "Repository name is required"
[[ -z "$GITHUB_USER" ]] && error "Not logged in to GitHub. Run 'gh auth login' first"
[[ -n "$STACK" && "$STACK" != "python" && "$STACK" != "js" ]] && error "Unknown stack: $STACK (use 'python' or 'js')"

REPO_FULL="$GITHUB_USER/$REPO_NAME"
REPO_DIR="$CLONE_DIR/$REPO_NAME"

# ─── Pre-flight checks ──────────────────────────────────────────────────────
[[ -d "$REPO_DIR" ]] && error "Directory already exists: $REPO_DIR"
if gh repo view "$REPO_FULL" &>/dev/null; then
  error "Repository $REPO_FULL already exists on GitHub"
fi

# ─── Create repository ──────────────────────────────────────────────────────
info "Creating $VISIBILITY repository: $REPO_FULL"
gh repo create "$REPO_FULL" --"$VISIBILITY" --clone --description "" -p "" 2>/dev/null \
  || gh repo create "$REPO_FULL" --"$VISIBILITY" --clone 2>/dev/null \
  || true

# gh repo create --clone may place it in cwd; move if needed
if [[ -d "./$REPO_NAME" && ! -d "$REPO_DIR" ]]; then
  mkdir -p "$CLONE_DIR"
  mv "./$REPO_NAME" "$REPO_DIR"
fi

# If clone didn't happen, clone manually
if [[ ! -d "$REPO_DIR/.git" ]]; then
  mkdir -p "$CLONE_DIR"
  gh repo clone "$REPO_FULL" "$REPO_DIR" 2>/dev/null || git clone "git@github.com:$REPO_FULL.git" "$REPO_DIR"
fi

cd "$REPO_DIR"
ok "Repository created and cloned to $REPO_DIR"

# ─── Copy common templates ──────────────────────────────────────────────────
info "Applying common templates..."
cp -rn "$TEMPLATES_DIR/common/." ./ 2>/dev/null || cp -r --no-clobber "$TEMPLATES_DIR/common/." ./

# Rename LICENSE
if [[ -f "LICENSE-MIT" && ! -f "LICENSE" ]]; then
  mv LICENSE-MIT LICENSE
fi

# ─── Copy stack overlay ─────────────────────────────────────────────────────
if [[ -n "$STACK" ]]; then
  info "Applying $STACK stack overlay..."
  cp -rn "$TEMPLATES_DIR/$STACK/." ./ 2>/dev/null || cp -r --no-clobber "$TEMPLATES_DIR/$STACK/." ./
fi

# ─── Replace placeholders ───────────────────────────────────────────────────
info "Replacing placeholders..."
find . -type f -not -path './.git/*' | while read -r f; do
  replace_placeholders "$f"
done

# ─── Apply security settings ────────────────────────────────────────────────
info "Applying security settings..."
"$TOOLKIT_DIR/bin/secure-repo.sh" "$REPO_FULL" --quiet

# ─── Disable unused features ────────────────────────────────────────────────
info "Configuring repository settings..."
gh repo edit "$REPO_FULL" --enable-wiki=false --enable-projects=false 2>/dev/null || true

# ─── Initial commit ─────────────────────────────────────────────────────────
info "Creating initial commit..."
git add -A
git commit -m "Initial commit from dev-toolkit

Stack: ${STACK:-none}
Visibility: $VISIBILITY

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"

git push -u origin main 2>/dev/null || git push -u origin "$(git branch --show-current)"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
ok "✨ Repository ready: https://github.com/$REPO_FULL"
echo "   Local: $REPO_DIR"
[[ -n "$STACK" ]] && echo "   Stack: $STACK"
echo "   Visibility: $VISIBILITY"
echo ""
echo "   Next steps:"
echo "   - Edit README.md with project description"
[[ "$STACK" == "python" ]] && echo "   - Run 'uv init' or edit pyproject.toml"
[[ "$STACK" == "js" ]] && echo "   - Run 'pnpm init' or add package.json"
echo "   - Update .github/copilot-instructions.md for this project"
