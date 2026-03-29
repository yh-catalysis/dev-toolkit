#!/usr/bin/env bash
set -euo pipefail

# ─── new-repo.sh ─────────────────────────────────────────────────────────────
# All-in-one script to bootstrap and secure a GitHub repository.
#
# Detects the current state and fills in only what's missing:
#   1. No directory       → create dir + apply templates + create GitHub repo
#   2. Directory exists   → add missing templates + git init (if needed)
#   3. Git initialized    → add missing templates + configure GitHub remote
#   4. Remote configured  → add missing templates + apply security settings
#
# Usage: ./bin/new-repo.sh <repo-name|path> [--stack python|js] [--public|--private]
# ─────────────────────────────────────────────────────────────────────────────

TOOLKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$TOOLKIT_DIR/templates"

# ─── Defaults ────────────────────────────────────────────────────────────────
VISIBILITY="private"
STACK=""
TARGET=""
GITHUB_USER="$(gh api user --jq '.login' 2>/dev/null || echo '')"
YEAR="$(date +%Y)"
CLONE_DIR="${DEV_TOOLKIT_CLONE_DIR:-$HOME/projects/github/personal}"
ADDED_FILES=()
SKIPPED_FILES=()

# ─── Helpers ─────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") <repo-name|path> [OPTIONS]

Arguments:
  <repo-name|path>      Repository name (created under --clone-dir) or
                         path to an existing directory

Options:
  --stack <python|js|dotnet>  Apply language-specific overlay
  --public              Create as public repository (default: private)
  --private             Create as private repository
  --clone-dir <path>    Clone destination (default: $CLONE_DIR)
  -h, --help            Show this help

Examples:
  # Brand new project
  $(basename "$0") my-tool --stack python --public

  # Existing directory (with or without git init)
  $(basename "$0") ./my-existing-project --stack js

  # .NET project
  $(basename "$0") my-solver --stack dotnet

  # Just a name — applies to \$CLONE_DIR/<name>
  $(basename "$0") my-app --stack python
EOF
  exit 0
}

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$1"; }
ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$1"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$1"; }
skip()  { printf '\033[1;90m[SKIP]\033[0m  %s\n' "$1"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; exit 1; }

# Copy a single template file only if the destination does not exist.
# Tracks what was added vs skipped for the summary.
copy_if_missing() {
  local src="$1" dest="$2"
  if [[ -e "$dest" ]]; then
    SKIPPED_FILES+=("$dest")
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  ADDED_FILES+=("$dest")
  return 0
}

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

# Recursively copy template directory, skipping existing files.
apply_template_layer() {
  local tmpl_dir="$1" target_dir="$2"
  while IFS= read -r -d '' src; do
    local rel="${src#"$tmpl_dir"/}"
    copy_if_missing "$src" "$target_dir/$rel" || true
  done < <(find "$tmpl_dir" -type f -print0)
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
    *)           TARGET="$1"; shift ;;
  esac
done

[[ -z "$TARGET" ]] && error "Repository name or path is required"
[[ -z "$GITHUB_USER" ]] && error "Not logged in to GitHub. Run 'gh auth login' first"
[[ -n "$STACK" && "$STACK" != "python" && "$STACK" != "js" && "$STACK" != "dotnet" ]] && error "Unknown stack: $STACK (use 'python', 'js', or 'dotnet')"

# ─── Resolve target directory and repo name ──────────────────────────────────
if [[ "$TARGET" == */* || "$TARGET" == .* ]]; then
  REPO_DIR="$(cd "$TARGET" 2>/dev/null && pwd || echo "$TARGET")"
  REPO_NAME="$(basename "$REPO_DIR")"
else
  REPO_NAME="$TARGET"
  REPO_DIR="$CLONE_DIR/$REPO_NAME"
fi

REPO_FULL="$GITHUB_USER/$REPO_NAME"

# ─── Detect current state ───────────────────────────────────────────────────
HAS_DIR=false; HAS_GIT=false; HAS_REMOTE=false; HAS_GITHUB_REPO=false

[[ -d "$REPO_DIR" ]] && HAS_DIR=true
[[ -d "$REPO_DIR/.git" ]] && HAS_GIT=true
if $HAS_GIT; then
  REMOTE_URL="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo '')"
  [[ -n "$REMOTE_URL" ]] && HAS_REMOTE=true
fi
gh repo view "$REPO_FULL" &>/dev/null && HAS_GITHUB_REPO=true

echo ""
info "Detected state for '$REPO_NAME':"
echo "   Directory exists:  $HAS_DIR"
echo "   Git initialized:   $HAS_GIT"
echo "   Remote configured: $HAS_REMOTE"
echo "   GitHub repo exists: $HAS_GITHUB_REPO"
echo ""

# ─── Step 1: Ensure directory exists ─────────────────────────────────────────
if ! $HAS_DIR; then
  info "Creating directory: $REPO_DIR"
  mkdir -p "$REPO_DIR"
  ok "Directory created"
fi

cd "$REPO_DIR"

# ─── Step 2: Ensure git is initialized ───────────────────────────────────────
if ! $HAS_GIT; then
  info "Initializing git repository..."
  git init -b main --quiet
  ok "Git initialized"
  HAS_GIT=true
fi

# ─── Step 3: Apply common templates (skip existing files) ────────────────────
info "Checking common templates..."
apply_template_layer "$TEMPLATES_DIR/common" "$REPO_DIR"

# Rename LICENSE-MIT → LICENSE if both are missing
if [[ -f "$REPO_DIR/LICENSE-MIT" && ! -f "$REPO_DIR/LICENSE" ]]; then
  mv "$REPO_DIR/LICENSE-MIT" "$REPO_DIR/LICENSE"
fi
# Clean up LICENSE-MIT if LICENSE already existed
[[ -f "$REPO_DIR/LICENSE-MIT" ]] && rm "$REPO_DIR/LICENSE-MIT"

# ─── Step 4: Apply stack overlay (skip existing files) ───────────────────────
if [[ -n "$STACK" ]]; then
  info "Checking $STACK stack templates..."
  apply_template_layer "$TEMPLATES_DIR/$STACK" "$REPO_DIR"
fi

# ─── Step 5: Replace placeholders in newly added files only ──────────────────
for f in "${ADDED_FILES[@]}"; do
  replace_placeholders "$f"
done

# ─── Step 6: Ensure GitHub repository exists ─────────────────────────────────
if ! $HAS_GITHUB_REPO; then
  info "Creating $VISIBILITY GitHub repository: $REPO_FULL"
  gh repo create "$REPO_FULL" --"$VISIBILITY" --description "" 2>/dev/null \
    && ok "GitHub repository created" \
    || warn "Could not create GitHub repository"
  HAS_GITHUB_REPO=true
fi

# ─── Step 7: Ensure remote is configured ─────────────────────────────────────
if ! $HAS_REMOTE; then
  info "Adding remote origin..."
  git remote add origin "git@github.com:$REPO_FULL.git" 2>/dev/null \
    || git remote set-url origin "git@github.com:$REPO_FULL.git" 2>/dev/null \
    || true
  ok "Remote origin configured"
fi

# ─── Step 8: Apply GitHub security settings ──────────────────────────────────
info "Applying security settings..."
"$TOOLKIT_DIR/bin/secure-repo.sh" "$REPO_FULL" --quiet

info "Configuring repository settings..."
gh repo edit "$REPO_FULL" --enable-wiki=false --enable-projects=false 2>/dev/null || true

# ─── Step 9: Generate POST_SETUP.md checklist ───────────────────────────────
POST_SETUP="$REPO_DIR/POST_SETUP.md"
if [[ ${#ADDED_FILES[@]} -gt 0 ]] && [[ ! -f "$POST_SETUP" ]]; then
  info "Generating POST_SETUP.md..."
  {
    echo "# Post-Setup Checklist"
    echo ""
    echo "Generated by dev-toolkit on $(date -Idate)."
    echo "Delete this file once all steps are complete."
    echo ""
    echo "## Files added by template"
    echo ""
    for f in "${ADDED_FILES[@]}"; do
      echo "- \`${f#"$REPO_DIR"/}\`"
    done
    echo ""
    echo "## Before your initial commit"
    echo ""
    echo "- [ ] Review all generated files and adjust to your project"
    if [[ "$STACK" == "python" ]]; then
      echo "- [ ] Run \`uv sync\` to set up the virtual environment"
      echo "- [ ] Run \`uv run ruff check .\` and \`uv run ruff format --check .\`"
      echo "- [ ] Edit \`tests/test_smoke.py\` or add real tests, then run \`uv run pytest\`"
    fi
    echo "- [ ] Write a meaningful README.md"
    echo ""
    echo "## Commit & push"
    echo ""
    echo '```bash'
    echo "git add -A"
    echo "git commit -m 'initial commit'"
    echo "git push -u origin main"
    echo '```'
    echo ""
    echo "## After push"
    echo ""
    echo "- [ ] Verify CI passes on GitHub Actions"
    echo "- [ ] Delete this file: \`rm POST_SETUP.md\`"
  } > "$POST_SETUP"
  ADDED_FILES+=("$POST_SETUP")
  ok "POST_SETUP.md created — follow the checklist before committing"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "✨ Setup complete: $REPO_FULL"
echo "   Local:      $REPO_DIR"
echo "   GitHub:     https://github.com/$REPO_FULL"
[[ -n "$STACK" ]] && echo "   Stack:      $STACK"
echo "   Visibility: $VISIBILITY"
echo ""

if [[ ${#ADDED_FILES[@]} -gt 0 ]]; then
  echo "   Added files:"
  for f in "${ADDED_FILES[@]}"; do
    printf '     \033[1;32m+\033[0m %s\n' "${f#"$REPO_DIR"/}"
  done
fi

if [[ ${#SKIPPED_FILES[@]} -gt 0 ]]; then
  echo "   Already existed (skipped):"
  for f in "${SKIPPED_FILES[@]}"; do
    printf '     \033[1;90m-\033[0m %s\n' "${f#"$REPO_DIR"/}"
  done
fi

if [[ ${#ADDED_FILES[@]} -eq 0 ]]; then
  echo ""
  ok "All template files already present. Nothing to add."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
