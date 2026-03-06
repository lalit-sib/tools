#!/bin/bash

VERSION="${1}"
TASK_ID="${2}"

if [ -z "$VERSION" ] || [ -z "$TASK_ID" ]; then
  echo ""
  echo "  Usage: $0 <version> <task-id>"
  echo "  Example: $0 4.76.3 1234"
  echo ""
  exit 1
fi

BRANCH="CRM-${TASK_ID}-update-crm-common-components"
BREVO_DIR="$(pwd)"

NAMES=(
  "app-crm-frontend"
  "companies-frontend"
  "tasks-frontend"
  "contacts-frontend"
  "contacts-details-frontend"
  "deals-frontend › reports-dashboard"
  "deals-frontend › import-export"
  "deals-frontend › sales-components"
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

# All selected by default
SELECTED=(1 1 1 1 1 1 1 1)

# ─────────────────────────────────────────────────────────
# Interactive selection
# ─────────────────────────────────────────────────────────
while true; do
  clear
  echo ""
  echo "  Update @dtsl/crm-common-components → $VERSION"
  echo "  Branch: $BRANCH"
  echo ""
  echo "  Type number to toggle | a=all | n=none | Enter=confirm"
  echo "  ────────────────────────────────────────────────────────"
  for i in "${!NAMES[@]}"; do
    mark="[ ]"; [ "${SELECTED[$i]}" -eq 1 ] && mark="[x]"
    printf "  %d) %s  %s\n" $((i+1)) "$mark" "${NAMES[$i]}"
  done
  echo ""
  read -r -p "  > " input
  case "$input" in
    "") break ;;
    a)  for i in "${!SELECTED[@]}"; do SELECTED[$i]=1; done ;;
    n)  for i in "${!SELECTED[@]}"; do SELECTED[$i]=0; done ;;
    *)
      if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le "${#NAMES[@]}" ]; then
        idx=$((input-1))
        [ "${SELECTED[$idx]}" -eq 1 ] && SELECTED[$idx]=0 || SELECTED[$idx]=1
      fi
      ;;
  esac
done

clear

# ─────────────────────────────────────────────────────────
# Collect unique git roots that have at least one selection
# ─────────────────────────────────────────────────────────
UNIQUE_ROOTS=()
for i in "${!NAMES[@]}"; do
  [ "${SELECTED[$i]}" -ne 1 ] && continue
  GIT_ROOT="${GIT_ROOTS[$i]}"
  found=0
  for r in "${UNIQUE_ROOTS[@]}"; do [ "$r" = "$GIT_ROOT" ] && found=1 && break; done
  [ "$found" -eq 0 ] && UNIQUE_ROOTS+=("$GIT_ROOT")
done

if [ ${#UNIQUE_ROOTS[@]} -eq 0 ]; then
  echo "  No repos selected. Exiting."
  exit 0
fi

echo ""
echo "Selected repos:"
for i in "${!NAMES[@]}"; do
  [ "${SELECTED[$i]}" -eq 1 ] && echo "  • ${NAMES[$i]}"
done

# ─────────────────────────────────────────────────────────
# Clone any missing repos (sequential — avoids auth prompts overlapping)
# ─────────────────────────────────────────────────────────
echo ""
echo "Checking repos..."
for GIT_ROOT in "${UNIQUE_ROOTS[@]}"; do
  REPO="$BREVO_DIR/$GIT_ROOT"
  if [ -d "$REPO" ]; then
    echo "  found    $GIT_ROOT"
  else
    echo "  cloning  $GIT_ROOT..."
    git clone "https://github.com/DTSL/${GIT_ROOT}" "$REPO" 2>&1 | \
      awk -v p="  [clone] " '{print p $0}'
    if [ $? -ne 0 ]; then
      echo "  ERROR: Failed to clone $GIT_ROOT. Check your GitHub access."
      exit 1
    fi
    echo "  cloned   $GIT_ROOT"
  fi
done

# ─────────────────────────────────────────────────────────
# Update package.json files
# ─────────────────────────────────────────────────────────
echo ""
echo "Updating package.json..."
for i in "${!PKG_PATHS[@]}"; do
  [ "${SELECTED[$i]}" -ne 1 ] && continue
  PKG="$BREVO_DIR/${PKG_PATHS[$i]}"
  sed -i '' 's|"@dtsl/crm-common-components": "[^"]*"|"@dtsl/crm-common-components": "'"$VERSION"'"|' "$PKG"
  echo "  updated ${PKG_PATHS[$i]}"
done

# ─────────────────────────────────────────────────────────
# Process each git root: branch → install → commit → push
# ─────────────────────────────────────────────────────────
echo ""
echo "Creating branches, installing, committing, pushing..."
echo ""

for GIT_ROOT in "${UNIQUE_ROOTS[@]}"; do
  # Snapshot the files to stage for this root before spawning subshell
  FILES_TO_STAGE=()
  for i in "${!PKG_PATHS[@]}"; do
    [ "${SELECTED[$i]}" -ne 1 ] && continue
    [ "${GIT_ROOTS[$i]}" != "$GIT_ROOT" ] && continue
    FILES_TO_STAGE+=("${PKG_PATHS[$i]#"$GIT_ROOT/"}")
  done

  (
    REPO="$BREVO_DIR/$GIT_ROOT"
    LOG="[$GIT_ROOT]"
    cd "$REPO"

    echo "$LOG Creating branch $BRANCH..."
    if ! git checkout -b "$BRANCH" 2>&1 | awk -v p="$LOG " '{print p $0}'; then
      echo "$LOG ERROR: Could not create branch. It may already exist."
      exit 1
    fi

    echo "$LOG Running yarn install..."
    [ -d "node_modules/@dtsl/crm-common-components" ] && \
      chmod -R u+w "node_modules/@dtsl/crm-common-components" 2>/dev/null || true
    yarn install 2>&1 | grep -E "(error|Done in|success Saved)" | \
      awk -v p="$LOG " '{print p $0}'

    echo "$LOG Staging files..."
    git add "${FILES_TO_STAGE[@]}"
    [ -f yarn.lock ] && git add yarn.lock

    echo "$LOG Committing..."
    git commit -m "chore: update @dtsl/crm-common-components to $VERSION" | \
      awk -v p="$LOG " '{print p $0}'

    echo "$LOG Pushing $BRANCH..."
    git push -u origin "$BRANCH" 2>&1 | awk -v p="$LOG " '{print p $0}'

    echo "$LOG Done!"
  ) &
done

wait
echo ""
echo "Done! Branch '$BRANCH' created and pushed to all selected repos."
