#!/bin/bash

# ─── Colors ───────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ─── Defaults ─────────────────────────────────────────────
PACKAGE="@dtsl/crm-common-components"
VERSION=""; TASK_ID=""; DRY_RUN=false; SKIP_INSTALL=false

usage() {
  printf "\n  Usage: %s <version> <task-id> [options]\n\n" "$(basename "$0")"
  printf "  Options:\n"
  printf "    --package <name>   Package to update (default: @dtsl/crm-common-components)\n"
  printf "    --dry-run          Preview changes without applying them\n"
  printf "    --skip-install     Skip yarn install\n\n"
  printf "  Examples:\n"
  printf "    %s 4.76.3 1234\n" "$(basename "$0")"
  printf "    %s 4.76.3 1234 --dry-run\n" "$(basename "$0")"
  printf "    %s 15.0.3 5678 --package @dtsl/react-ui-components\n\n" "$(basename "$0")"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=true ;;
    --skip-install) SKIP_INSTALL=true ;;
    --package)      PACKAGE="$2"; shift ;;
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
LOG_FILE="$BREVO_DIR/.update-${PACKAGE_SHORT}-$(date +%Y%m%d-%H%M%S).log"
TMP_DIR=$(mktemp -d)
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

# ─── Header ───────────────────────────────────────────────
clear
printf "\n${BOLD}  update-dtsl-dep${NC}\n"
hr
printf "  Package  : ${CYAN}%s${NC}\n"  "$PACKAGE"
printf "  Version  : ${CYAN}%s${NC}\n"  "$VERSION"
printf "  Branch   : ${CYAN}%s${NC}\n"  "$BRANCH"
printf "  Dir      : ${DIM}%s${NC}\n"   "$BREVO_DIR"
printf "  Log      : ${DIM}%s${NC}\n"   "$LOG_FILE"
$DRY_RUN      && printf "  ${YELLOW}Mode     : DRY RUN — no changes will be made${NC}\n"
$SKIP_INSTALL && printf "  Mode     : --skip-install\n"
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
    if [ "${SELECTED[$i]}" -eq 1 ]; then
      printf "  ${GREEN}%d) [x]${NC}  %s\n" $((i+1)) "${NAMES[$i]}"
    else
      printf "  ${DIM}%d) [ ]  %s${NC}\n" $((i+1)) "${NAMES[$i]}"
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

# ─── STEP 3/5  Clone missing repos ────────────────────────
step "Clone missing repos"
for GR in "${UNIQUE_ROOTS[@]}"; do
  REPO="$BREVO_DIR/$GR"
  if [ -d "$REPO/.git" ]; then
    ok "$GR ${DIM}(exists)${NC}"
  else
    start_spinner "Cloning $GR..."
    if git clone "https://github.com/DTSL/${GR}" "$REPO" >> "$LOG_FILE" 2>&1; then
      stop_spinner; ok "$GR ${DIM}(cloned)${NC}"
    else
      stop_spinner; fail "Failed to clone $GR — check GitHub access"; exit 1
    fi
  fi
done

# ─── STEP 4/5  Safety checks ──────────────────────────────
step "Safety checks"
DIRTY_ROOTS=(); SKIP_ROOTS=()

for GR in "${UNIQUE_ROOTS[@]}"; do
  REPO="$BREVO_DIR/$GR"

  # Skip if all selected package.json files already have the target version
  already=true
  for i in "${!PKG_PATHS[@]}"; do
    [ "${SELECTED[$i]}" -ne 1 ] && continue
    [ "${GIT_ROOTS[$i]}" != "$GR" ] && continue
    grep -q "\"${PACKAGE}\": \"${VERSION}\"" "$BREVO_DIR/${PKG_PATHS[$i]}" 2>/dev/null \
      || { already=false; break; }
  done
  if $already; then
    warn "$GR — already on ${CYAN}${VERSION}${NC}, will skip"
    SKIP_ROOTS+=("$GR"); continue
  fi

  # Check for uncommitted/unstaged changes
  DIRTY=$(cd "$REPO" && git status --porcelain 2>/dev/null)
  if [ -n "$DIRTY" ]; then
    COUNT=$(printf "%s\n" "$DIRTY" | wc -l | tr -d ' ')
    warn "$GR — ${YELLOW}${COUNT} uncommitted change(s):${NC}"
    printf "%s\n" "$DIRTY" | head -5 | while read -r line; do
      printf "     ${DIM}%s${NC}\n" "$line"
    done
    [ "$COUNT" -gt 5 ] && printf "     ${DIM}(+%d more)${NC}\n" $((COUNT-5))
    DIRTY_ROOTS+=("$GR")
  else
    ok "$GR — clean"
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

# Confirm if any dirty repos
if [ ${#DIRTY_ROOTS[@]} -gt 0 ]; then
  printf "\n  ${YELLOW}${#DIRTY_ROOTS[@]} repo(s) have uncommitted changes.${NC} Proceed anyway? ${BOLD}[y/N]${NC} "
  read -r c; [[ "$c" =~ ^[Yy]$ ]] || { printf "  Aborted.\n"; exit 0; }
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

# Update package.json files
for i in "${!PKG_PATHS[@]}"; do
  [ "${SELECTED[$i]}" -ne 1 ] && continue
  skip=0; for s in "${SKIP_ROOTS[@]}"; do [ "${GIT_ROOTS[$i]}" = "$s" ] && skip=1 && break; done
  [ "$skip" -ne 0 ] && continue
  PKG="$BREVO_DIR/${PKG_PATHS[$i]}"
  sed -i '' "s|\"${PACKAGE}\": \"[^\"]*\"|\"${PACKAGE}\": \"${VERSION}\"|" "$PKG"
  info "Updated ${PKG_PATHS[$i]}"
done
printf "\n"

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

    # Pull latest default branch
    _p "Pulling latest..."
    DEFAULT_BR=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
      | sed 's@^refs/remotes/origin/@@' || echo "main")
    git pull origin "$DEFAULT_BR" >> "$LOG_FILE" 2>&1 \
      || _p "⚠ pull failed — continuing on current state"

    # Create feature branch
    _p "Creating branch ${BRANCH}..."
    git checkout -b "$BRANCH" >> "$LOG_FILE" 2>&1 \
      || { echo "failed|branch already exists — try a different task ID" > "$SF"; exit 0; }

    # yarn install
    if ! $SKIP_INSTALL; then
      _p "Running yarn install..."
      [ -d "node_modules/${PACKAGE}" ] && chmod -R u+w "node_modules/${PACKAGE}" 2>/dev/null || true
      yarn install >> "$LOG_FILE" 2>&1 \
        || { echo "failed|yarn install failed — check log for details" > "$SF"; exit 0; }
    fi

    # Commit
    _p "Committing..."
    git add "${FILES[@]}" >> "$LOG_FILE" 2>&1
    [ -f yarn.lock ] && git add yarn.lock >> "$LOG_FILE" 2>&1
    git commit -m "chore: update ${PACKAGE} to ${VERSION}" >> "$LOG_FILE" 2>&1 \
      || { echo "failed|nothing to commit" > "$SF"; exit 0; }

    # Push
    _p "Pushing ${BRANCH}..."
    git push -u origin "$BRANCH" >> "$LOG_FILE" 2>&1 \
      || { echo "failed|push failed — check auth or remote" > "$SF"; exit 0; }

    echo "success|" > "$SF"
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
    ERR=$(cut -d'|' -f2- "$SF")
    if [ "$ST" = "success" ]; then
      printf "  %-44s  ${GREEN}✓ pushed → %s${NC}\n" "$GR" "$BRANCH"
      SUCCESS=$((SUCCESS+1))
    else
      printf "  %-44s  ${RED}✗ %s${NC}\n" "$GR" "$ERR"
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
printf "\n  ${DIM}Log: %s${NC}\n\n" "$LOG_FILE"
