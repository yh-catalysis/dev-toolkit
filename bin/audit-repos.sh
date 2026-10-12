#!/usr/bin/env bash
set -euo pipefail

# ─── audit-repos.sh ─────────────────────────────────────────────────────────
# Audit repositories for security and configuration compliance.
# Usage: ./bin/audit-repos.sh [--visibility all|public|private] [--affiliation <list>]
#                             [--include-archived] [--public-only] [--user <username>]
# ─────────────────────────────────────────────────────────────────────────────

# ─── Defaults ────────────────────────────────────────────────────────────────
USER=""
VIS_FILTER="all"       # --visibility
AFF_FILTER="owner"     # --affiliation
VIS_GIVEN=false
AFF_GIVEN=false
INCLUDE_ARCHIVED=false
ISSUES_FOUND=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Choose which repositories to audit:
  --visibility <all|public|private>
                        Public repos, private repos, or both (default: all)
  --affiliation <list>  Your relationship to the repo, comma-separated (default: owner)
                          owner                You own the repo
                          collaborator         Someone else's repo you were invited to
                          organization_member  A repo of an organization you belong to
                          all                  All of the above
  --include-archived    Also audit archived repos (skipped by default: they are
                        read-only, so their warnings cannot be acted on)
  --public-only         Same as --visibility public
  --user <username>     Audit another account instead of yourself. GitHub lists only
                        the public repos that account owns, so this cannot be combined
                        with --visibility private|all or --affiliation other than owner.
  -h, --help            Show this help

Some checks need admin access to the repo (Dependabot alerts, Dependabot security
updates, security features). They are skipped where you are not an admin, which is
usually the case for collaborator and organization_member repos.

Examples:
  # Every repo you own, public and private
  $(basename "$0")

  # Only your public repos
  $(basename "$0") --public-only

  # Private repos you own or were invited to
  $(basename "$0") --visibility private --affiliation owner,collaborator
EOF
  exit 0
}

die() { echo "$1" >&2; exit 1; }
need_value() { [[ $# -ge 2 && -n "$2" ]] || die "$1 needs a value (see --help)"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)        need_value "$@"; USER="$2"; shift 2 ;;
    --visibility)  need_value "$@"; VIS_FILTER="$2"; VIS_GIVEN=true; shift 2 ;;
    --affiliation) need_value "$@"; AFF_FILTER="$2"; AFF_GIVEN=true; shift 2 ;;
    --public-only) VIS_FILTER="public"; VIS_GIVEN=true; shift ;;
    --include-archived) INCLUDE_ARCHIVED=true; shift ;;
    -h|--help)     usage ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

case "$VIS_FILTER" in
  all|public|private) ;;
  *) die "--visibility must be all, public, or private (got: $VIS_FILTER)" ;;
esac

[[ "$AFF_FILTER" == "all" ]] && AFF_FILTER="owner,collaborator,organization_member"
IFS=',' read -ra AFF_VALUES <<< "$AFF_FILTER"
[[ ${#AFF_VALUES[@]} -gt 0 ]] || die "--affiliation needs at least one value (see --help)"
for AFF in "${AFF_VALUES[@]}"; do
  case "$AFF" in
    owner|collaborator|organization_member) ;;
    *) die "--affiliation accepts owner, collaborator, organization_member, or all (got: $AFF)" ;;
  esac
done

ME="$(gh api user --jq '.login' 2>/dev/null || true)"
[[ -z "$ME" ]] && die "Could not determine your GitHub account. Run: gh auth login"
[[ -z "$USER" ]] && USER="$ME"

OTHER_ACCOUNT=false
if [[ "${USER,,}" != "${ME,,}" ]]; then
  OTHER_ACCOUNT=true
  if { $VIS_GIVEN && [[ "$VIS_FILTER" != "public" ]]; } || { $AFF_GIVEN && [[ "$AFF_FILTER" != "owner" ]]; }; then
    die "For another account (--user $USER), GitHub lists only the public repos it owns. Drop --visibility / --affiliation, or use --public-only."
  fi
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────
warn_item() { printf '    \033[1;33m⚠\033[0m  %s\n' "$1"; ISSUES_FOUND=$((ISSUES_FOUND + 1)); }
ok_item()   { printf '    \033[1;32m✓\033[0m  %s\n' "$1"; }
skip_item() { printf '    \033[2m-  %s\033[0m\n' "$1"; }
header()    { printf '\n\033[1;36m━━ %s\033[0m\n' "$1"; }

# Succeed if any of the given paths exists in the repo (stops at the first hit).
has_any_file() {
  local repo="$1" path; shift
  for path in "$@"; do
    gh api "repos/$repo/contents/$path" --silent 2>/dev/null && return 0
  done
  return 1
}

# ─── Fetch repos ─────────────────────────────────────────────────────────────
QUERY='.[] | [.full_name, .visibility, .license.spdx_id // "NONE", .default_branch, (.has_wiki|tostring), (.permissions.admin // false | tostring), (.archived|tostring)] | @tsv'
if $OTHER_ACCOUNT; then
  # /users/{user}/repos returns public repos only, even to an authenticated caller
  SCOPE="public repos owned by $USER"
  REPOS="$(gh api "users/$USER/repos?per_page=100&type=owner&sort=updated" --paginate --jq "$QUERY" 2>/dev/null)"
else
  # /user/repos also returns private repos, filtered by visibility and affiliation
  SCOPE="visibility=$VIS_FILTER, affiliation=$AFF_FILTER"
  REPOS="$(gh api "user/repos?per_page=100&visibility=$VIS_FILTER&affiliation=$AFF_FILTER&sort=updated" --paginate --jq "$QUERY" 2>/dev/null)"
fi

# Archived repos are read-only, so their warnings cannot be acted on
ARCHIVED_SKIPPED=0
if $INCLUDE_ARCHIVED; then
  SCOPE+=", archived included"
else
  SCOPE+=", archived excluded"
  ARCHIVED_SKIPPED="$(awk -F'\t' '$7 == "true" { n++ } END { print n + 0 }' <<< "$REPOS")"
  REPOS="$(awk -F'\t' '$7 != "true"' <<< "$REPOS")"
fi
ARCHIVED_NOTE=""
[[ "$ARCHIVED_SKIPPED" -gt 0 ]] && ARCHIVED_NOTE="Archived repos skipped: $ARCHIVED_SKIPPED (add --include-archived to audit them)"

[[ -z "$REPOS" ]] && { echo "No repositories found ($SCOPE)"; [[ -n "$ARCHIVED_NOTE" ]] && echo "$ARCHIVED_NOTE"; exit 0; }

TOTAL=0
echo ""
printf '\033[1m🔍 Repository Audit for %s\033[0m\n' "$USER"
printf '   Scope: %s\n' "$SCOPE"
printf '   Date: %s\n' "$(date -Iseconds)"

# ─── Check each repo ────────────────────────────────────────────────────────
while IFS=$'\t' read -r FULL_NAME VISIBILITY LICENSE DEFAULT_BRANCH HAS_WIKI IS_ADMIN ARCHIVED; do
  TOTAL=$((TOTAL + 1))
  NOTES="$VISIBILITY"
  [[ "$ARCHIVED" == "true" ]] && NOTES+=", archived"
  [[ "$IS_ADMIN" == "true" ]] || NOTES+=", not admin"
  header "$FULL_NAME ($NOTES)"

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

  # Security features (public repos). The API shows them to admins only.
  if [[ "$VISIBILITY" == "public" && "$IS_ADMIN" != "true" ]]; then
    skip_item "Security features: not checked (needs admin access)"
  elif [[ "$VISIBILITY" == "public" ]]; then
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

  # Dependabot or Renovate (not both: they open duplicate update PRs)
  HAS_DEPBOT=false
  has_any_file "$FULL_NAME" .github/dependabot.yml .github/dependabot.yaml && HAS_DEPBOT=true

  HAS_RENOVATE=false
  has_any_file "$FULL_NAME" renovate.json renovate.json5 .github/renovate.json .github/renovate.json5 \
    .renovaterc .renovaterc.json .renovaterc.json5 && HAS_RENOVATE=true

  if $HAS_DEPBOT && $HAS_RENOVATE; then
    warn_item "Both dependabot.yml and Renovate are configured (duplicate update PRs)"
  elif $HAS_DEPBOT; then
    ok_item "Dependency updates: Dependabot"
  elif $HAS_RENOVATE; then
    ok_item "Dependency updates: Renovate"
  else
    warn_item "No dependency update tool (Dependabot/Renovate) configured"
  fi

  # Dependabot alerts (Renovate's vulnerabilityAlerts opens security PRs from them).
  # Non-admins get 404 here even when alerts are enabled, so don't guess.
  if [[ "$IS_ADMIN" != "true" ]]; then
    skip_item "Dependabot alerts: not checked (needs admin access)"
  else
    gh api "repos/$FULL_NAME/vulnerability-alerts" --silent 2>/dev/null \
      && ok_item "Dependabot alerts enabled" \
      || warn_item "Dependabot alerts disabled"
  fi

  # Dependabot security updates duplicate Renovate's security PRs (admin-only API, too)
  if $HAS_RENOVATE && [[ "$IS_ADMIN" != "true" ]]; then
    skip_item "Dependabot security updates: not checked (needs admin access)"
  elif $HAS_RENOVATE; then
    DSU="$(gh api "repos/$FULL_NAME/automated-security-fixes" --jq '.enabled' 2>/dev/null || true)"
    [[ "$DSU" == "true" ]] \
      && warn_item "Dependabot security updates enabled alongside Renovate (duplicate security PRs)" \
      || ok_item "Dependabot security updates disabled (Renovate opens security PRs)"
  fi

  # Dependency graph job: for some lockfiles (e.g. uv.lock) Dependabot resolves the
  # dependencies in Actions ("Dependency Graph", dynamic/dependabot/update-graph).
  # While it keeps failing, the graph keeps the last successful result, so alerts go
  # stale. A known cause is a requires-python lower bound with a patch version newer
  # than Dependabot's Python (tool_version_not_supported).
  GRAPH_WF="$(gh api "repos/$FULL_NAME/actions/workflows" --paginate \
    --jq '.workflows[] | select(.path == "dynamic/dependabot/update-graph") | .id' 2>/dev/null || true)"
  if [[ -n "$GRAPH_WF" ]]; then
    GRAPH_RUNS="$(gh api "repos/$FULL_NAME/actions/workflows/$GRAPH_WF/runs?status=completed&per_page=20" \
      --jq '[.workflow_runs[] | .conclusion] as $c
            | ($c | map(. == "failure") | index(false) // length) as $n
            | ([.workflow_runs[] | select(.conclusion == "success")][0].created_at) as $ok
            | [$n, (if $ok then $ok[:10] else "none in the last 20 runs" end)]
            | @tsv' 2>/dev/null || true)"
    IFS=$'\t' read -r GRAPH_FAILS GRAPH_LAST_OK <<< "$GRAPH_RUNS"
    if [[ "${GRAPH_FAILS:-0}" -gt 0 ]]; then
      warn_item "Dependency graph job failing ($GRAPH_FAILS run(s) in a row, last success: $GRAPH_LAST_OK); check the 'Dependency Graph' runs in Actions"
    elif [[ -n "$GRAPH_RUNS" ]]; then
      ok_item "Dependency graph job succeeding"
    fi
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
[[ -n "$ARCHIVED_NOTE" ]] && echo "   $ARCHIVED_NOTE"
if [[ $ISSUES_FOUND -eq 0 ]]; then
  printf '   \033[1;32m✓ No issues found\033[0m\n'
else
  printf '   \033[1;33m⚠ %d issue(s) found\033[0m\n' "$ISSUES_FOUND"
fi
echo ""
