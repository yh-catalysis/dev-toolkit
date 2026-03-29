#!/usr/bin/env bash
set -euo pipefail

# ─── audit-repos.sh ─────────────────────────────────────────────────────────
# Audit all repositories for security and configuration compliance.
# Usage: ./bin/audit-repos.sh [--user <username>] [--public-only]
# ─────────────────────────────────────────────────────────────────────────────

USER=""
PUBLIC_ONLY=false
ISSUES_FOUND=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)        USER="$2"; shift 2 ;;
    --public-only) PUBLIC_ONLY=true; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--user <username>] [--public-only]"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$USER" ]] && USER="$(gh api user --jq '.login' 2>/dev/null)"
[[ -z "$USER" ]] && { echo "Could not determine GitHub user. Use --user <username>" >&2; exit 1; }

# ─── Helpers ─────────────────────────────────────────────────────────────────
warn_item() { printf '    \033[1;33m⚠\033[0m  %s\n' "$1"; ISSUES_FOUND=$((ISSUES_FOUND + 1)); }
ok_item()   { printf '    \033[1;32m✓\033[0m  %s\n' "$1"; }
header()    { printf '\n\033[1;36m━━ %s\033[0m\n' "$1"; }

# ─── Fetch repos ─────────────────────────────────────────────────────────────
QUERY='.[] | [.full_name, .visibility, .license.spdx_id // "NONE", .default_branch, (.has_wiki|tostring)] | @tsv'
REPOS="$(gh api "users/$USER/repos?per_page=100&type=owner&sort=updated" --paginate --jq "$QUERY" 2>/dev/null)"

if $PUBLIC_ONLY; then
  REPOS="$(echo "$REPOS" | grep -P '\tpublic\t' || true)"
fi

[[ -z "$REPOS" ]] && { echo "No repositories found for $USER"; exit 0; }

TOTAL=0
echo ""
printf '\033[1m🔍 Repository Audit for %s\033[0m\n' "$USER"
printf '   Date: %s\n' "$(date -Iseconds)"

# ─── Check each repo ────────────────────────────────────────────────────────
while IFS=$'\t' read -r FULL_NAME VISIBILITY LICENSE DEFAULT_BRANCH HAS_WIKI; do
  TOTAL=$((TOTAL + 1))
  header "$FULL_NAME ($VISIBILITY)"

  # License
  if [[ "$VISIBILITY" == "public" ]]; then
    [[ "$LICENSE" == "NONE" ]] && warn_item "No license" || ok_item "License: $LICENSE"
  fi

  # Wiki (should be disabled)
  [[ "$HAS_WIKI" == "true" ]] && warn_item "Wiki is enabled (usually unnecessary)" || ok_item "Wiki disabled"

  # SECURITY.md
  gh api "repos/$FULL_NAME/contents/.github/SECURITY.md" --silent 2>/dev/null \
    && ok_item "SECURITY.md present" \
    || gh api "repos/$FULL_NAME/contents/SECURITY.md" --silent 2>/dev/null \
      && ok_item "SECURITY.md present" \
      || { [[ "$VISIBILITY" == "public" ]] && warn_item "No SECURITY.md" || true; }

  # Security features (public repos)
  if [[ "$VISIBILITY" == "public" ]]; then
    SEC="$(gh api "repos/$FULL_NAME" --jq '.security_and_analysis' 2>/dev/null || echo '{}')"
    if echo "$SEC" | grep -q '"status":"enabled"' 2>/dev/null; then
      SS="$(echo "$SEC" | python3 -c "import sys,json; d=json.load(sys.stdin) or {}; print(d.get('secret_scanning',{}).get('status','?'))" 2>/dev/null || echo '?')"
      PP="$(echo "$SEC" | python3 -c "import sys,json; d=json.load(sys.stdin) or {}; print(d.get('secret_scanning_push_protection',{}).get('status','?'))" 2>/dev/null || echo '?')"
      [[ "$SS" == "enabled" ]] && ok_item "Secret scanning enabled" || warn_item "Secret scanning not enabled"
      [[ "$PP" == "enabled" ]] && ok_item "Push protection enabled" || warn_item "Push protection not enabled"
    else
      warn_item "Security features not configured"
    fi
  fi

  # Dependabot or Renovate
  HAS_DEPBOT=false
  gh api "repos/$FULL_NAME/contents/.github/dependabot.yml" --silent 2>/dev/null && HAS_DEPBOT=true
  gh api "repos/$FULL_NAME/contents/.github/dependabot.yaml" --silent 2>/dev/null && HAS_DEPBOT=true

  HAS_RENOVATE=false
  gh api "repos/$FULL_NAME/contents/renovate.json" --silent 2>/dev/null && HAS_RENOVATE=true
  gh api "repos/$FULL_NAME/contents/.renovaterc.json" --silent 2>/dev/null && HAS_RENOVATE=true

  if $HAS_DEPBOT || $HAS_RENOVATE; then
    ok_item "Dependency updates: $(${HAS_DEPBOT} && echo 'Dependabot')$(${HAS_DEPBOT} && ${HAS_RENOVATE} && echo ' + ')$(${HAS_RENOVATE} && echo 'Renovate')"
  else
    warn_item "No dependency update tool (Dependabot/Renovate) configured"
  fi

  # GitHub Actions SHA pinning check
  WORKFLOWS="$(gh api "repos/$FULL_NAME/contents/.github/workflows" --jq '.[].name' 2>/dev/null || true)"
  if [[ -n "$WORKFLOWS" ]]; then
    UNPINNED=0
    while IFS= read -r WF; do
      CONTENT="$(gh api "repos/$FULL_NAME/contents/.github/workflows/$WF" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)"
      # Find 'uses:' lines with tag references (v1, v2, @main, @master) instead of SHA
      TAG_REFS="$(echo "$CONTENT" | grep -E 'uses:\s+\S+@' | grep -vE '@[0-9a-f]{40}' | grep -vE '^\s*#' || true)"
      if [[ -n "$TAG_REFS" ]]; then
        UNPINNED=$((UNPINNED + 1))
        warn_item "Unpinned actions in $WF"
      fi
    done <<< "$WORKFLOWS"
    [[ $UNPINNED -eq 0 ]] && ok_item "All actions are SHA-pinned"
  fi

done <<< "$REPOS"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
printf '\033[1m━━ Summary ━━\033[0m\n'
echo "   Repositories checked: $TOTAL"
if [[ $ISSUES_FOUND -eq 0 ]]; then
  printf '   \033[1;32m✓ No issues found\033[0m\n'
else
  printf '   \033[1;33m⚠ %d issue(s) found\033[0m\n' "$ISSUES_FOUND"
fi
echo ""
