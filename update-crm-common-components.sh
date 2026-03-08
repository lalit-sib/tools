#!/bin/bash

# ─── Colors ───────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ─── Defaults ─────────────────────────────────────────────
PACKAGE="@dtsl/crm-common-components"
VERSION=""; TASK_ID=""; DRY_RUN=false; SKIP_INSTALL=false; FORCE_INSTALL=false

usage() {
  printf "\n  Usage: %s <version> <task-id> [options]\n\n" "$(basename "$0")"
  printf "  Options:\n"
  printf "    --package <name>   Package to update (default: @dtsl/crm-common-components)\n"
  printf "    --dry-run          Preview changes without applying them\n"
  printf "    --skip-install     Skip yarn install\n"
  printf "    --force-install    Run yarn install --force\n\n"
  printf "  Examples:\n"
  printf "    %s 4.76.3 1234\n" "$(basename "$0")"
  printf "    %s 4.76.3 1234 --dry-run\n" "$(basename "$0")"
  printf "    %s 15.0.3 5678 --package @dtsl/react-ui-components\n\n" "$(basename "$0")"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=true ;;
    --skip-install)   SKIP_INSTALL=true ;;
    --force-install)  FORCE_INSTALL=true ;;
    --package)        PACKAGE="$2"; shift ;;
    -h|--help)      usage ;;
    -*)             printf "  Unknown flag: %s\n" "$1"; usage ;;
    *)  [ -z "$VERSION" ] && VERSION="$1" || TASK_ID="$1" ;;
  esac
  shift
done
{ [ -z "$VERSION" ] || [ -z "$TASK_ID" ]; } && usage

PACKAGE_SHORT="${PACKAGE##*/}"
BRANCH="CRM-${TASK_ID}-update-${PACKAGE_SHORT}"
BREVO_DIR="$(pwd)"
TMP_DIR=$(mktemp -d)
LOG_FILE="$TMP_DIR/run.log"
ERR_LOG="$BREVO_DIR/.update-${PACKAGE_SHORT}-$(date +%Y%m%d-%H%M%S).log"
trap 'rm -rf "$TMP_DIR"' EXIT

# ─── UI helpers ───────────────────────────────────────────
STEP=0; TOTAL=5

_log()  { printf "%b\n" "$*" | perl -pe 's/\e\[[0-9;]*m//g' >> "$LOG_FILE"; }
step()  {
  STEP=$((STEP+1))
  printf "\n${BOLD}[%d/%d] %s${NC}\n" "$STEP" "$TOTAL" "$*"
  _log "\n[${STEP}/${TOTAL}] $*\n----------------------------------------"
}
ok()    { printf "  ${GREEN}✓${NC}  %b\n" "$*";      _log "  ✓  $*"; }
fail()  { printf "  ${RED}✗${NC}  %b\n" "$*";       _log "  ✗  $*"; }
warn()  { printf "  ${YELLOW}⚠${NC}  %b\n" "$*";    _log "  ⚠  $*"; }
info()  { printf "  ${CYAN}→${NC}  %b\n" "$*";      _log "  →  $*"; }
dry()   { printf "  ${DIM}∅  %b${NC}\n" "$*"; }
hr()    { printf "  ${DIM}─────────────────────────────────────────${NC}\n"; }

SPINNER_PID=""
start_spinner() {
  local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0 msg="$1"
  (while true; do
    printf "\r  ${CYAN}%s${NC}  %s" "${f[$((i % 10))]}" "$msg"
    i=$((i+1)); sleep 0.08
  done) & SPINNER_PID=$!
}
stop_spinner() {
  [ -n "$SPINNER_PID" ] && { kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null; }
  SPINNER_PID=""; printf "\r\033[K"
}

# ─── Repo table ───────────────────────────────────────────
NAMES=(
  "app-crm-frontend"
  "companies-frontend"
  "tasks-frontend"
  "contacts-frontend"
  "contacts-details-frontend"
  "deals-frontend/apps/reports-dashboard"
  "deals-frontend/apps/import-export"
  "deals-frontend/apps/sales-components"
)
PKG_PATHS=(
  "app-crm-frontend/package.json"
  "companies-frontend/package.json"
  "tasks-frontend/package.json"
  "contacts-frontend/package.json"
  "contacts-details-frontend/package.json"
  "deals-frontend/apps/reports-dashboard/package.json"
  "deals-frontend/apps/import-export/package.json"
  "deals-frontend/apps/sales-components/package.json"
)
GIT_ROOTS=(
  "app-crm-frontend"
  "companies-frontend"
  "tasks-frontend"
  "contacts-frontend"
  "contacts-details-frontend"
  "deals-frontend"
  "deals-frontend"
  "deals-frontend"
)
SELECTED=(1 1 1 1 1 1 1 1)

# ─── Pre-compute current branch per git root ──────────────
declare -A ROOT_BRANCH
for GR in "app-crm-frontend" "companies-frontend" "tasks-frontend" \
           "contacts-frontend" "contacts-details-frontend" "deals-frontend"; do
  REPO="$BREVO_DIR/$GR"
  if [ -d "$REPO/.git" ]; then
    ROOT_BRANCH[$GR]=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  else
    ROOT_BRANCH[$GR]="not cloned"
  fi
done

# ─── Header ───────────────────────────────────────────────
clear
printf "\n${BOLD}  update-dtsl-dep${NC}\n"
hr
printf "  Package  : ${CYAN}%s${NC}\n"  "$PACKAGE"
printf "  Version  : ${CYAN}%s${NC}\n"  "$VERSION"
printf "  Branch   : ${CYAN}%s${NC}\n"  "$BRANCH"
printf "  Dir      : ${DIM}%s${NC}\n"   "$BREVO_DIR"
$DRY_RUN      && printf "  ${YELLOW}Mode     : DRY RUN — no changes will be made${NC}\n"
$SKIP_INSTALL && printf "  Mode     : --skip-install\n"
$FORCE_INSTALL && printf "  Mode     : --force-install\n"
hr

printf "update-dtsl-dep | %s\nPackage: %s | Version: %s | Branch: %s\nDry-run: %s | Dir: %s\n\n" \
  "$(date)" "$PACKAGE" "$VERSION" "$BRANCH" "$DRY_RUN" "$BREVO_DIR" > "$LOG_FILE"

# ─── STEP 1/5  Registry check ─────────────────────────────
step "Verify ${PACKAGE}@${VERSION} on registry"
start_spinner "Querying npm.pkg.github.com..."
if npm view "${PACKAGE}@${VERSION}" version \
    --registry=https://npm.pkg.github.com 2>/dev/null | grep -q "$VERSION"; then
  stop_spinner
  ok "${PACKAGE}@${VERSION} found on registry"
else
  stop_spinner
  warn "Could not confirm ${PACKAGE}@${VERSION} — private registry may need auth"
  printf "\n  Continue anyway? ${BOLD}[y/N]${NC} "; read -r c
  [[ "$c" =~ ^[Yy]$ ]] || { printf "  Aborted.\n"; exit 0; }
fi

# ─── STEP 2/5  Select repos ───────────────────────────────
while true; do
  clear
  printf "\n${BOLD}  Select repos${NC}  ${DIM}(%s → %s | branch: %s)${NC}\n\n" \
    "$PACKAGE" "$VERSION" "$BRANCH"
  printf "  Toggle: number | ${BOLD}a${NC}=all | ${BOLD}n${NC}=none | ${BOLD}Enter${NC}=confirm\n"
  hr
  for i in "${!NAMES[@]}"; do
    br="${ROOT_BRANCH[${GIT_ROOTS[$i]}]}"
    if [ "${SELECTED[$i]}" -eq 1 ]; then
      printf "  ${GREEN}%d) [x]${NC}  %-44s ${DIM}(%s)${NC}\n" $((i+1)) "${NAMES[$i]}" "$br"
    else
      printf "  ${DIM}%d) [ ]  %-44s (%s)${NC}\n" $((i+1)) "${NAMES[$i]}" "$br"
    fi
  done
  printf "\n  > "; read -r inp
  case "$inp" in
    "") break ;;
    a)  for i in "${!SELECTED[@]}"; do SELECTED[$i]=1; done ;;
    n)  for i in "${!SELECTED[@]}"; do SELECTED[$i]=0; done ;;
    *)
      if [[ "$inp" =~ ^[0-9]+$ ]] && (( inp >= 1 && inp <= ${#NAMES[@]} )); then
        idx=$((inp-1))
        [ "${SELECTED[$idx]}" -eq 1 ] && SELECTED[$idx]=0 || SELECTED[$idx]=1
      fi ;;
  esac
done

# Dedupe git roots from selection
UNIQUE_ROOTS=()
for i in "${!NAMES[@]}"; do
  [ "${SELECTED[$i]}" -ne 1 ] && continue
  GR="${GIT_ROOTS[$i]}"; found=0
  for r in "${UNIQUE_ROOTS[@]}"; do [ "$r" = "$GR" ] && found=1 && break; done
  [ "$found" -eq 0 ] && UNIQUE_ROOTS+=("$GR")
done

clear
step "Repos selected"
if [ ${#UNIQUE_ROOTS[@]} -eq 0 ]; then warn "No repos selected. Exiting."; exit 0; fi
for i in "${!NAMES[@]}"; do
  [ "${SELECTED[$i]}" -eq 1 ] \
    && ok "${NAMES[$i]}" \
    || printf "  ${DIM}  ○  %s${NC}\n" "${NAMES[$i]}"
done

# ─── STEP 3/5  Clone / prepare repos ─────────────────────
SKIP_ROOTS=()
step "Clone / prepare repos"
for GR in "${UNIQUE_ROOTS[@]}"; do
  REPO="$BREVO_DIR/$GR"
  if [ -d "$REPO/.git" ]; then
    DIRTY=$(git -C "$REPO" status --porcelain 2>/dev/null)
    CURR_BR=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    printf "\n  ${CYAN}[%s]${NC}  on ${BOLD}%s${NC}" "$GR" "$CURR_BR"
    [ -n "$DIRTY" ] && printf "  ${YELLOW}(dirty)${NC}"
    printf "\n  Stash changes and switch to dev? ${BOLD}[y/N]${NC} "; read -r c
    if [[ "$c" =~ ^[Yy]$ ]]; then
      if [ -n "$DIRTY" ]; then
        start_spinner "Stashing $GR..."
        git -C "$REPO" stash push -m "auto-stash: update-dtsl-dep $(date +%Y%m%d)" >> "$LOG_FILE" 2>&1
        stop_spinner; ok "Stashed $(printf "%s\n" "$DIRTY" | wc -l | tr -d ' ') change(s)"
      fi
      start_spinner "Switching to dev..."
      if git -C "$REPO" checkout dev >> "$LOG_FILE" 2>&1; then
        stop_spinner
        start_spinner "Pulling dev..."
        git -C "$REPO" pull origin dev >> "$LOG_FILE" 2>&1
        stop_spinner; ok "$GR — on dev, pulled"
      elif git -C "$REPO" checkout main >> "$LOG_FILE" 2>&1; then
        stop_spinner
        start_spinner "Pulling main..."
        git -C "$REPO" pull origin main >> "$LOG_FILE" 2>&1
        stop_spinner; warn "$GR — dev not found, on main, pulled"
      else
        stop_spinner; warn "$GR — could not switch to dev or main, staying on $CURR_BR"
      fi
    else
      if [ -n "$DIRTY" ]; then
        COUNT=$(printf "%s\n" "$DIRTY" | wc -l | tr -d ' ')
        warn "$GR — $COUNT uncommitted change(s). Continue with dirty state? ${BOLD}[y/N]${NC} "; read -r d
        if [[ "$d" =~ ^[Yy]$ ]]; then
          ok "$GR — using $CURR_BR (with uncommitted changes)"
        else
          warn "$GR — skipped"
          SKIP_ROOTS+=("$GR"); continue
        fi
      else
        ok "$GR — using current branch $CURR_BR"
      fi
    fi
  else
    start_spinner "Cloning $GR..."
    cloned=false
    for try_branch in dev main; do
      git clone --branch "$try_branch" "https://github.com/DTSL/${GR}" "$REPO" >> "$LOG_FILE" 2>&1 \
        && { cloned=true; break; } || rm -rf "$REPO"
    done
    $cloned || { git clone "https://github.com/DTSL/${GR}" "$REPO" >> "$LOG_FILE" 2>&1 && cloned=true; }
    if $cloned; then
      stop_spinner
      CLONED_BR=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
      ok "$GR ${DIM}(cloned on ${CLONED_BR})${NC}"
    else
      stop_spinner; fail "Failed to clone $GR — check GitHub access"
      cp "$LOG_FILE" "$ERR_LOG" 2>/dev/null && printf "  ${DIM}Log: %s${NC}\n" "$ERR_LOG"; exit 1
    fi
  fi
done

# Remove repos the user skipped during prepare step
NEW_ROOTS=()
for r in "${UNIQUE_ROOTS[@]}"; do
  skip=0; for s in "${SKIP_ROOTS[@]}"; do [ "$r" = "$s" ] && skip=1 && break; done
  [ "$skip" -eq 0 ] && NEW_ROOTS+=("$r")
done
UNIQUE_ROOTS=("${NEW_ROOTS[@]}")
[ ${#UNIQUE_ROOTS[@]} -eq 0 ] && { warn "No repos to process. Exiting."; exit 0; }

# ─── STEP 4/5  Safety checks ──────────────────────────────
step "Safety checks"

for GR in "${UNIQUE_ROOTS[@]}"; do
  REPO="$BREVO_DIR/$GR"

  # Skip if all selected package.json files already have the target version committed
  already=true
  for i in "${!PKG_PATHS[@]}"; do
    [ "${SELECTED[$i]}" -ne 1 ] && continue
    [ "${GIT_ROOTS[$i]}" != "$GR" ] && continue
    rel_path="${PKG_PATHS[$i]#"$GR/"}"
    git -C "$REPO" show HEAD:"$rel_path" 2>/dev/null \
      | grep -q "\"${PACKAGE}\": \"${VERSION}\"" \
      || { already=false; break; }
  done
  if $already; then
    warn "$GR — already on ${CYAN}${VERSION}${NC} (committed), will skip"
    SKIP_ROOTS+=("$GR")
  else
    ok "$GR — ready"
  fi
done

# Remove skipped roots from processing list
NEW_ROOTS=()
for r in "${UNIQUE_ROOTS[@]}"; do
  skip=0; for s in "${SKIP_ROOTS[@]}"; do [ "$r" = "$s" ] && skip=1 && break; done
  [ "$skip" -eq 0 ] && NEW_ROOTS+=("$r")
done
UNIQUE_ROOTS=("${NEW_ROOTS[@]}")

if [ ${#UNIQUE_ROOTS[@]} -eq 0 ]; then
  printf "\n"; ok "All selected repos already on ${VERSION}. Nothing to do."; exit 0
fi

# ─── STEP 5/5  Update → branch → install → commit → push ──
$SKIP_INSTALL \
  && step "Update → branch → commit → push" \
  || step "Update → branch → install → commit → push"

# Dry-run: preview and exit
if $DRY_RUN; then
  dry "Would update package.json in:"
  for i in "${!PKG_PATHS[@]}"; do
    [ "${SELECTED[$i]}" -ne 1 ] && continue
    skip=0; for s in "${SKIP_ROOTS[@]}"; do [ "${GIT_ROOTS[$i]}" = "$s" ] && skip=1 && break; done
    [ "$skip" -eq 0 ] && dry "    ${PKG_PATHS[$i]}  (${YELLOW}current → ${VERSION}${NC})"
  done
  printf "\n"
  dry "Branch : ${BRANCH}"
  dry "Commit : chore: update ${PACKAGE} to ${VERSION}"
  dry "Push   : origin/${BRANCH}"
  printf "\n"; ok "Dry run complete — no changes made."; exit 0
fi

# Parallel git ops — one subshell per git root
for GR in "${UNIQUE_ROOTS[@]}"; do
  # Snapshot files to stage before spawning subshell
  FILES=()
  for i in "${!PKG_PATHS[@]}"; do
    [ "${SELECTED[$i]}" -ne 1 ] && continue
    [ "${GIT_ROOTS[$i]}" != "$GR" ] && continue
    FILES+=("${PKG_PATHS[$i]#"$GR/"}")
  done
  SF="$TMP_DIR/${GR//\//_}"

  (
    REPO="$BREVO_DIR/$GR"; cd "$REPO"
    _l() { printf "%s [%s] %s\n" "$(date +%H:%M:%S)" "$GR" "$*" >> "$LOG_FILE"; }
    _p() { printf "  ${CYAN}[%s]${NC} %s\n" "$GR" "$*"; _l "$*"; }

    # Update package.json files (while still on current branch / dev)
    for f in "${FILES[@]}"; do
      sed -i '' "s|\"${PACKAGE}\": \"[^\"]*\"|\"${PACKAGE}\": \"${VERSION}\"|" "$REPO/$f"
      _p "Updated $f"
    done

    # Create feature branch (skip if already on it)
    CURR_BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    BRANCH_NEW=true
    if [ "$CURR_BR" = "$BRANCH" ]; then
      _p "Already on ${BRANCH}, skipping branch creation"
      BRANCH_NEW=false
    else
      _p "Creating branch ${BRANCH}..."
      branch_out=$(git checkout -b "$BRANCH" 2>&1)
      echo "$branch_out" >> "$LOG_FILE"
      if [ $? -ne 0 ]; then
        reason=$(echo "$branch_out" | grep -v '^$' | tail -1)
        echo "failed|branch already exists — try a different task ID${reason:+ ($reason)}" > "$SF"; exit 0
      fi
    fi

    # yarn install
    if ! $SKIP_INSTALL; then
      YARN_FLAGS=""; $FORCE_INSTALL && YARN_FLAGS="--force"
      _p "Running yarn install${YARN_FLAGS:+ $YARN_FLAGS}..."
      [ -d "node_modules/${PACKAGE}" ] && chmod -R u+w "node_modules/${PACKAGE}" 2>/dev/null || true
      yarn_out=$(yarn install $YARN_FLAGS 2>&1)
      echo "$yarn_out" >> "$LOG_FILE"
      if [ $? -ne 0 ]; then
        reason=$(echo "$yarn_out" | grep -i "error\|failed" | grep -v "^$" | tail -1 | sed 's/^[[:space:]]*//')
        echo "failed|yarn install failed${reason:+ — $reason}" > "$SF"; exit 0
      fi
    fi

    # Commit
    _p "Committing..."
    git add "${FILES[@]}" >> "$LOG_FILE" 2>&1
    [ -f yarn.lock ] && git add yarn.lock >> "$LOG_FILE" 2>&1
    commit_out=$(git commit -m "chore: update ${PACKAGE} to ${VERSION}" 2>&1)
    echo "$commit_out" >> "$LOG_FILE"
    if [ $? -ne 0 ]; then
      reason=$(echo "$commit_out" | grep -v '^$' | tail -1 | sed 's/^[[:space:]]*//')
      echo "failed|nothing to commit${reason:+ ($reason)}" > "$SF"; exit 0
    fi

    # Push
    _p "Pushing ${BRANCH}..."
    push_out=$(git push -u origin "$BRANCH" 2>&1)
    echo "$push_out" >> "$LOG_FILE"
    if [ $? -ne 0 ]; then
      reason=$(echo "$push_out" | grep -i "error\|rejected\|failed" | grep -v "^$" | tail -1 | sed 's/^[[:space:]]*//')
      echo "failed|push failed${reason:+ — $reason}" > "$SF"; exit 0
    fi

    # Create draft PR (skip if one already exists for this branch)
    _p "Creating draft PR..."
    existing_pr=$(gh api "repos/DTSL/${GR}/pulls?head=DTSL:${BRANCH}&state=open" \
      --jq '.[0].html_url' 2>/dev/null)
    if [ -n "$existing_pr" ] && [ "$existing_pr" != "null" ]; then
      PR_URL="$existing_pr"
      _p "PR already exists: $PR_URL"
    else
      PR_URL=$(gh api "repos/DTSL/${GR}/pulls" \
        --method POST \
        -f title="CRM-${TASK_ID}: update ${PACKAGE_SHORT} to version ${VERSION}" \
        -f body="" \
        -f head="${BRANCH}" \
        -f base="dev" \
        -F draft=true \
        --jq '.html_url' 2>>"$LOG_FILE")
      if [ -n "$PR_URL" ] && [ "$PR_URL" != "null" ]; then
        _p "Draft PR: $PR_URL"
      else
        _p "⚠ Could not create PR — check log"
        PR_URL=""
      fi
    fi

    $BRANCH_NEW && echo "success|new|${PR_URL}" > "$SF" || echo "success|existing|${PR_URL}" > "$SF"
    _p "✓ Done"
  ) &
done

wait

# ─── Summary ──────────────────────────────────────────────
printf "\n"; hr
printf "\n${BOLD}  Summary${NC}\n\n"
printf "  %-44s  %s\n" "Repo" "Status"
printf "  %-44s  %s\n" "--------------------------------------------" "------------------------"

SUCCESS=0; FAILED=0; SKIPPED=0

for GR in "${UNIQUE_ROOTS[@]}"; do
  SF="$TMP_DIR/${GR//\//_}"
  if [ -f "$SF" ]; then
    ST=$(cut -d'|' -f1 "$SF")
    BR_ST=$(cut -d'|' -f2 "$SF")
    PR_URL=$(cut -d'|' -f3 "$SF")
    if [ "$ST" = "success" ]; then
      [ "$BR_ST" = "new" ] \
        && printf "  %-44s  ${GREEN}✓ pushed → %s${NC}\n" "$GR" "$BRANCH" \
        || printf "  %-44s  ${GREEN}✓ pushed to existing %s${NC}\n" "$GR" "$BRANCH"
      [ -n "$PR_URL" ] \
        && printf "  %-44s    ${DIM}%s${NC}\n" "" "$PR_URL"
      SUCCESS=$((SUCCESS+1))
    else
      printf "  %-44s  ${RED}✗ %s${NC}\n" "$GR" "$BR_ST"
      FAILED=$((FAILED+1))
    fi
  fi
done

for SR in "${SKIP_ROOTS[@]}"; do
  printf "  %-44s  ${YELLOW}— already on %s${NC}\n" "$SR" "$VERSION"
  SKIPPED=$((SKIPPED+1))
done

printf "\n"
[ "$SUCCESS" -gt 0 ] && printf "  ${GREEN}${SUCCESS} pushed${NC}   "
[ "$FAILED"  -gt 0 ] && printf "  ${RED}${FAILED} failed${NC}   "
[ "$SKIPPED" -gt 0 ] && printf "  ${YELLOW}${SKIPPED} skipped${NC}"
printf "\n"
if [ "$FAILED" -gt 0 ]; then
  cp "$LOG_FILE" "$ERR_LOG" 2>/dev/null && printf "  ${DIM}Log: %s${NC}\n" "$ERR_LOG"
fi
printf "\n"
