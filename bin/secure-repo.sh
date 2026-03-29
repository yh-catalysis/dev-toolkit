#!/usr/bin/env bash
set -euo pipefail

# ─── secure-repo.sh ─────────────────────────────────────────────────────────
# Idempotently apply security settings to an existing GitHub repository.
# Usage: ./bin/secure-repo.sh <owner/repo> [--quiet]
# ─────────────────────────────────────────────────────────────────────────────

QUIET=false
REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) QUIET=true; shift ;;
    -*)      echo "Unknown option: $1" >&2; exit 1 ;;
    *)       REPO="$1"; shift ;;
  esac
done

[[ -z "$REPO" ]] && { echo "Usage: $(basename "$0") <owner/repo> [--quiet]" >&2; exit 1; }

info()  { $QUIET || printf '\033[1;34m[INFO]\033[0m  %s\n' "$1"; }
ok()    { $QUIET || printf '\033[1;32m[OK]\033[0m    %s\n' "$1"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$1"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; }

# ─── Detect visibility ──────────────────────────────────────────────────────
VISIBILITY="$(gh repo view "$REPO" --json visibility --jq '.visibility' 2>/dev/null || echo 'UNKNOWN')"
info "Repository: $REPO (${VISIBILITY})"

# ─── Security features (available for public repos or with GHAS) ────────────
if [[ "$VISIBILITY" == "PUBLIC" ]]; then
  info "Enabling secret scanning..."
  gh api -X PUT "repos/$REPO/secret-scanning" 2>/dev/null || true

  info "Enabling security settings..."
  gh api -X PATCH "repos/$REPO" \
    -f security_and_analysis[secret_scanning][status]=enabled \
    -f security_and_analysis[secret_scanning_push_protection][status]=enabled \
    --silent 2>/dev/null && ok "Secret scanning + push protection enabled" \
    || warn "Could not enable secret scanning (may already be enabled)"

  info "Enabling Dependabot security updates..."
  gh api -X PUT "repos/$REPO/automated-security-fixes" --silent 2>/dev/null \
    && ok "Dependabot security updates enabled" \
    || warn "Could not enable Dependabot security updates"

  info "Enabling Dependabot vulnerability alerts..."
  gh api -X PUT "repos/$REPO/vulnerability-alerts" --silent 2>/dev/null \
    && ok "Vulnerability alerts enabled" \
    || warn "Could not enable vulnerability alerts"
else
  info "Private repo — secret scanning and Dependabot alerts via API are limited"
  info "Enabling vulnerability alerts..."
  gh api -X PUT "repos/$REPO/vulnerability-alerts" --silent 2>/dev/null \
    && ok "Vulnerability alerts enabled" \
    || warn "Could not enable vulnerability alerts"
fi

# ─── Branch protection (main branch) ────────────────────────────────────────
DEFAULT_BRANCH="$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo 'main')"
info "Setting branch protection on '$DEFAULT_BRANCH'..."

gh api -X PUT "repos/$REPO/branches/$DEFAULT_BRANCH/protection" \
  -F required_status_checks=null \
  -F enforce_admins=false \
  -F required_pull_request_reviews=null \
  -F restrictions=null \
  -F allow_force_pushes=false \
  -F allow_deletions=false \
  --silent 2>/dev/null \
  && ok "Branch protection: force-push and deletion blocked on '$DEFAULT_BRANCH'" \
  || warn "Could not set branch protection (may require GitHub Pro for private repos)"

# ─── Delete head branches on merge ──────────────────────────────────────────
info "Enabling auto-delete head branches..."
gh repo edit "$REPO" --delete-branch-on-merge 2>/dev/null \
  && ok "Auto-delete head branches enabled" \
  || warn "Could not enable auto-delete head branches"

$QUIET || echo ""
$QUIET || ok "Security configuration complete for $REPO"
