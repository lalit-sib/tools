#!/bin/bash

# ─── Colors ───────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ─── UI helpers ───────────────────────────────────────────
hr()   { printf "  ${DIM}─────────────────────────────────────────${NC}\n"; }
ok()   { printf "  ${GREEN}✓${NC}  %b\n" "$*"; }
fail() { printf "  ${RED}✗${NC}  %b\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC}  %b\n" "$*"; }

BREVO_DIR="$(pwd)"
MFE_CONTAINER="$BREVO_DIR/micro-frontend-container"
STAGING_CONFIG="$MFE_CONTAINER/public/mfeconfig/staging_mfeconfig.json"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ─── Hardcoded mapping: path|git_root|app_name ────────────
# Derived from staging_mfeconfig.json inspection.
# Each row = one JSON entry that needs its url updated.
# deals-frontend/apps/sales-components intentionally omitted.
ENTRIES=(
  "/companies                           | companies-frontend          | du-companies"
  "/tasks                               | tasks-frontend              | du-tasks-frontend"
  "/crm                                 | app-crm-frontend            | du-app-crm-frontend"
  "/crm/dashboard                       | deals-frontend              | du-crm-dashboard-frontend"
  "/crm/onboarding                      | deals-frontend              | du-deals-onboarding"
  "/import-export                       | deals-frontend              | du-crm-import-export-frontend"
  "/contact/index                       | contacts-details-frontend   | du-contacts-details-frontend"
  "/contact/settings/visible-attributes | contacts-details-frontend   | du-contacts-details-frontend"
  "/contact                             | contacts-frontend           | du-contacts-frontend"
)

# ─── Verify prereqs ───────────────────────────────────────
if [ ! -d "$MFE_CONTAINER/.git" ]; then
  printf "\n"; fail "micro-frontend-container not found at $MFE_CONTAINER"; exit 1
fi
if [ ! -f "$STAGING_CONFIG" ]; then
  printf "\n"; fail "staging_mfeconfig.json not found at $STAGING_CONFIG"; exit 1
fi

# ─── Derive unique git roots (order-preserving, bash 3 safe) ─
UNIQUE_ROOTS=()
for entry in "${ENTRIES[@]}"; do
  GR=$(echo "$entry" | awk -F'|' '{gsub(/ /,"",$2); print $2}')
  found=false
  for r in "${UNIQUE_ROOTS[@]+"${UNIQUE_ROOTS[@]}"}"; do
    [ "$r" = "$GR" ] && { found=true; break; }
  done
  $found || UNIQUE_ROOTS+=("$GR")
done
N_ROOTS=${#UNIQUE_ROOTS[@]}

# ─── Pre-compute current branch per root (parallel array) ─
ROOT_BRANCH_VALS=()
for GR in "${UNIQUE_ROOTS[@]}"; do
  REPO="$BREVO_DIR/$GR"
  if [ -d "$REPO/.git" ]; then
    ROOT_BRANCH_VALS+=("$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")")
  else
    ROOT_BRANCH_VALS+=("not cloned")
  fi
done

# ─── Parallel-array helpers (bash 3 safe, no declare -A) ──
# REPO_FMT_VALS[i] mirrors UNIQUE_ROOTS[i]
REPO_FMT_VALS=()
for ((i=0; i<N_ROOTS; i++)); do REPO_FMT_VALS[$i]="__unset__"; done

_get_fmt() {
  local target="$1"
  for ((i=0; i<N_ROOTS; i++)); do
    [ "${UNIQUE_ROOTS[$i]}" = "$target" ] && { printf "%s" "${REPO_FMT_VALS[$i]}"; return; }
  done
}
_set_fmt() {
  local target="$1" val="$2"
  for ((i=0; i<N_ROOTS; i++)); do
    [ "${UNIQUE_ROOTS[$i]}" = "$target" ] && { REPO_FMT_VALS[$i]="$val"; return; }
  done
}
_is_selected() {
  local target="$1"
  for ((i=0; i<N_ROOTS; i++)); do
    [ "${UNIQUE_ROOTS[$i]}" = "$target" ] && [ "${SEL[$i]}" -eq 1 ] && return 0
  done
  return 1
}

# ─── Repo selection (full clear-screen loop) ──────────────
SEL=()
for ((i=0; i<N_ROOTS; i++)); do SEL[$i]=1; done

while true; do
  clear
  printf "\n${BOLD}  update-staging-mfeconfig${NC}  ${DIM}Select repos to update${NC}\n\n"
  printf "  Toggle: number | ${BOLD}a${NC}=all | ${BOLD}n${NC}=none | ${BOLD}Enter${NC}=confirm\n"
  hr
  for ((i=0; i<N_ROOTS; i++)); do
    br="${ROOT_BRANCH_VALS[$i]}"
    if [ "${SEL[$i]}" -eq 1 ]; then
      printf "  ${GREEN}%d) [x]${NC}  %-36s ${DIM}(%s)${NC}\n" $((i+1)) "${UNIQUE_ROOTS[$i]}" "$br"
    else
      printf "  ${DIM}%d) [ ]  %-36s (%s)${NC}\n" $((i+1)) "${UNIQUE_ROOTS[$i]}" "$br"
    fi
  done
  printf "\n  > "; read -r inp
  case "$inp" in
    "") break ;;
    a)  for ((i=0; i<N_ROOTS; i++)); do SEL[$i]=1; done ;;
    n)  for ((i=0; i<N_ROOTS; i++)); do SEL[$i]=0; done ;;
    *)
      if [[ "$inp" =~ ^[0-9]+$ ]] && (( inp >= 1 && inp <= N_ROOTS )); then
        idx=$((inp-1))
        [ "${SEL[$idx]}" -eq 1 ] && SEL[$idx]=0 || SEL[$idx]=1
      fi ;;
  esac
done

n_sel=0
for ((i=0; i<N_ROOTS; i++)); do [ "${SEL[$i]}" -eq 1 ] && n_sel=$((n_sel+1)); done
[ "$n_sel" -eq 0 ] && { printf "\n"; fail "No repos selected."; exit 1; }

# ─── Selection summary ─────────────────────────────────────
clear
printf "\n${BOLD}  update-staging-mfeconfig${NC}\n"
hr
printf "  Dir      : ${DIM}%s${NC}\n" "$BREVO_DIR"
hr
printf "\n${BOLD}  Repos selected${NC}\n"; hr
for ((i=0; i<N_ROOTS; i++)); do
  if [ "${SEL[$i]}" -eq 1 ]; then
    ok "${UNIQUE_ROOTS[$i]}  ${DIM}(${ROOT_BRANCH_VALS[$i]})${NC}"
  else
    printf "  ${DIM}  ○  %s${NC}\n" "${UNIQUE_ROOTS[$i]}"
  fi
done

# ─── Auto-detect task ID from selected repos' branches ────
AUTO_IDS=()
for ((i=0; i<N_ROOTS; i++)); do
  [ "${SEL[$i]}" -eq 1 ] || continue
  id=$(echo "${ROOT_BRANCH_VALS[$i]}" | grep -oE 'CRM-[0-9]+' | head -1 | sed 's/CRM-//')
  [ -z "$id" ] && continue
  found=false
  for d in "${AUTO_IDS[@]+"${AUTO_IDS[@]}"}"; do
    [ "$d" = "$id" ] && { found=true; break; }
  done
  $found || AUTO_IDS+=("$id")
done

printf "\n"
if [ ${#AUTO_IDS[@]} -eq 1 ]; then
  TASK_ID="${AUTO_IDS[0]}"
  printf "  Task ID  : ${CYAN}%s${NC}  ${DIM}(auto-detected)${NC}\n" "$TASK_ID"
else
  [ ${#AUTO_IDS[@]} -gt 1 ] && warn "Multiple task IDs found: ${AUTO_IDS[*]}"
  printf "  Enter task ID: "; read -r TASK_ID
  [ -z "$TASK_ID" ] && { fail "Task ID required."; exit 1; }
fi

BRANCH="CRM-${TASK_ID}-update-staging-mfeconfig"
printf "  Branch   : ${CYAN}%s${NC}\n" "$BRANCH"
hr

# ─── [1/3] Compute public paths ───────────────────────────
printf "\n${BOLD}  [1/3] Computing public paths${NC}\n"; hr

for entry in "${ENTRIES[@]}"; do
  GR=$(echo "$entry" | awk -F'|' '{gsub(/ /,"",$2); print $2}')
  _is_selected "$GR" || continue
  [ "$(_get_fmt "$GR")" != "__unset__" ] && continue   # already processed for this root

  REPO="$BREVO_DIR/$GR"
  if [ ! -d "$REPO/.git" ]; then
    warn "${GR} — not cloned, will skip"; _set_fmt "$GR" ""; continue
  fi

  RAW_BR=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -z "$RAW_BR" ]; then
    warn "${GR} — could not read branch"; _set_fmt "$GR" ""; continue
  fi

  # Replicate CF_PAGES_BRANCH logic (matches .github/workflows cloudflare-pages.yml):
  # replace / and _ with -, truncate to 28, strip trailing -, lowercase
  FMT=$(printf "%s" "$RAW_BR" | sed 's/[\/]/-/g' | sed 's/_/-/g' | cut -c1-28 | sed 's/-$//' | tr '[:upper:]' '[:lower:]')
  _set_fmt "$GR" "$FMT"
  ok "${GR}  ${DIM}${RAW_BR} → ${FMT}${NC}"
done

# ─── Show planned URL updates ─────────────────────────────
printf "\n${BOLD}  Planned URL updates${NC}\n"; hr
printf "  %-44s  %s\n" "Path" "New URL"
printf "  %-44s  %s\n" "--------------------------------------------" "------"

UPDATES_FILE="$TMP_DIR/updates.txt"
for entry in "${ENTRIES[@]}"; do
  PATH_KEY=$(echo "$entry" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
  GR=$(echo "$entry"       | awk -F'|' '{gsub(/ /,"",$2); print $2}')
  APP=$(echo "$entry"      | awk -F'|' '{gsub(/ /,"",$3); print $3}')

  if ! _is_selected "$GR"; then
    printf "  ${DIM}%-44s  (skipped — not selected)${NC}\n" "$PATH_KEY"; continue
  fi

  FMT="$(_get_fmt "$GR")"
  if [ -z "$FMT" ]; then
    printf "  ${DIM}%-44s  (skipped — repo not available)${NC}\n" "$PATH_KEY"; continue
  fi

  NEW_URL="https://${FMT}--${APP}.pages.51b.dev/remoteEntryContainer.js"
  printf "  ${CYAN}%-44s${NC}  ${DIM}%s${NC}\n" "$PATH_KEY" "$NEW_URL"
  printf "%s %s\n" "$PATH_KEY" "$NEW_URL" >> "$UPDATES_FILE"
done

# ─── [2/3] Prepare mfe-container + apply updates ─────────
printf "\n${BOLD}  [2/3] Preparing micro-frontend-container${NC}\n"; hr

DIRTY=$(git -C "$MFE_CONTAINER" status --porcelain 2>/dev/null)
if [ -n "$DIRTY" ]; then
  git -C "$MFE_CONTAINER" stash push -m "auto-stash: update-staging-mfeconfig $(date +%Y%m%d)" > /dev/null 2>&1
  ok "Stashed $(printf "%s\n" "$DIRTY" | wc -l | tr -d ' ') change(s)"
fi

if git -C "$MFE_CONTAINER" checkout dev > /dev/null 2>&1; then
  ok "Switched to dev"
  git -C "$MFE_CONTAINER" pull origin dev > /dev/null 2>&1 && ok "Pulled latest"
else
  warn "Could not checkout dev — staying on current branch"
fi

# Apply URL updates using Python — surgical text replacement, preserves all formatting
python3 - "$STAGING_CONFIG" "$UPDATES_FILE" << 'PYEOF'
import json, sys

config_path, updates_path = sys.argv[1], sys.argv[2]

updates = {}
with open(updates_path) as f:
    for line in f:
        parts = line.strip().split(' ', 1)
        if len(parts) == 2:
            updates[parts[0]] = parts[1]

with open(config_path) as f:
    content = f.read()

# Parse JSON only to map old_url → new_url; replace in raw text to preserve formatting
data = json.loads(content)
for entry in data:
    path = entry.get('path', '')
    if path in updates:
        old_url = entry.get('url', '')
        new_url = updates[path]
        if old_url and old_url != new_url:
            content = content.replace(
                '"url": "{}"'.format(old_url),
                '"url": "{}"'.format(new_url)
            )

with open(config_path, 'w') as f:
    f.write(content)
PYEOF

if [ $? -ne 0 ]; then
  fail "Failed to update staging_mfeconfig.json"; exit 1
fi
ok "staging_mfeconfig.json updated"

# ─── Show diff & ask for verification ─────────────────────
printf "\n${BOLD}  Diff${NC}\n"; hr
git -C "$MFE_CONTAINER" diff --color=always -- public/mfeconfig/staging_mfeconfig.json
hr

printf "\n  Verify the changes above. Proceed to commit and create draft PR? ${BOLD}[y/N]${NC} "
read -r c
[[ "$c" =~ ^[Yy]$ ]] || { warn "Aborted — changes left uncommitted on dev."; exit 0; }

# ─── [3/3] Branch → commit → push → draft PR ─────────────
printf "\n${BOLD}  [3/3] Commit and push${NC}\n"; hr

CURR_BR=$(git -C "$MFE_CONTAINER" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$CURR_BR" = "$BRANCH" ]; then
  ok "Already on ${BRANCH}"
else
  branch_out=$(git -C "$MFE_CONTAINER" checkout -b "$BRANCH" 2>&1)
  if [ $? -ne 0 ]; then
    fail "Failed to create branch — $(echo "$branch_out" | grep -v '^$' | tail -1)"; exit 1
  fi
  ok "Created branch ${BRANCH}"
fi

git -C "$MFE_CONTAINER" add "public/mfeconfig/staging_mfeconfig.json"
commit_out=$(git -C "$MFE_CONTAINER" commit -m "chore: update staging mfeconfig for CRM-${TASK_ID}" 2>&1)
if [ $? -ne 0 ]; then
  fail "Commit failed — $(echo "$commit_out" | grep -v '^$' | tail -1)"; exit 1
fi
ok "Committed"

push_out=$(git -C "$MFE_CONTAINER" push -u origin "$BRANCH" 2>&1)
if [ $? -ne 0 ]; then
  reason=$(echo "$push_out" | grep -i "error\|rejected\|failed" | grep -v '^$' | tail -1 | sed 's/^[[:space:]]*//')
  fail "Push failed${reason:+ — $reason}"; exit 1
fi
ok "Pushed ${BRANCH}"

printf "  Creating draft PR...\n"
existing_pr=$(gh api "repos/DTSL/micro-frontend-container/pulls?head=DTSL:${BRANCH}&state=open" \
  --jq '.[0].html_url' 2>/dev/null)
if [ -n "$existing_pr" ] && [ "$existing_pr" != "null" ]; then
  ok "PR already exists: ${existing_pr}"
else
  PR_URL=$(gh api "repos/DTSL/micro-frontend-container/pulls" \
    --method POST \
    -f title="CRM-${TASK_ID}: update crm common components" \
    -f body="" \
    -f head="${BRANCH}" \
    -f base="dev" \
    -F draft=true \
    --jq '.html_url' 2>/dev/null)
  if [ -n "$PR_URL" ] && [ "$PR_URL" != "null" ]; then
    ok "Draft PR: ${PR_URL}"
  else
    warn "Could not create PR — check gh auth and repo access"
  fi
fi

printf "\n"; hr; printf "\n"
