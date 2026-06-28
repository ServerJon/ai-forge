#!/usr/bin/env bash
#
# ai-forge installer
# -----------------------------------------------------------------------------
# Interactive installer for ai-forge skills and agents.
#
#   ./install.sh -p /path/to/your-project
#
# Behaviour (see install.md for the full spec):
#   * Requires a target project path (-p flag or interactive prompt).
#   * Presents an arrow-key / spacebar checkbox tree of agents, skills and
#     helper commands.
#   * Resolves dependencies, skips already-installed items, copies the
#     selected SKILL.md / agent files into the project's .agents/ folder,
#     drops a pre-filled AGENTS.md, and prints a summary with next steps.
#
# Compatible with Bash 3.2 (default macOS shell) -- no associative arrays,
# no mapfile.
# -----------------------------------------------------------------------------

set -uo pipefail

# Absolute path to this repo (the source of skills/agents).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Terminal helpers
# -----------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ -n "${TERM:-}" ]; then
  C_RESET="$(tput sgr0)"
  C_BOLD="$(tput bold)"
  C_DIM="$(tput dim)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"
  C_RED="$(tput setaf 1)"
  C_CYAN="$(tput setaf 6)"
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_RED=""; C_CYAN=""
fi

info()  { printf '%s\n' "${C_BLUE}==>${C_RESET} $*"; }
ok()    { printf '%s\n' "${C_GREEN}✓${C_RESET} $*"; }
dry()   { printf '%s\n' "${C_CYAN}[dry-run]${C_RESET} $*"; }
warn()  { printf '%s\n' "${C_YELLOW}!${C_RESET} $*" >&2; }
err()   { printf '%s\n' "${C_RED}✗${C_RESET} $*" >&2; }
die()   { err "$*"; exit 1; }

# -----------------------------------------------------------------------------
# Menu data model (parallel arrays, indexed by row)
# -----------------------------------------------------------------------------
LBL=()        # display label (without checkbox/indent)
TYPE=()       # cat | sub | skill | agent | readme | cmd
SUB=()        # parent subfolder name (skills/<sub> or agents/<sub>)
NAME=()       # leaf name (skill/agent/command id)
SRC=()        # source path on disk (file or directory)
PARENT=()     # index of immediate parent, or -1
DEPTH=()      # indentation depth
CHECKED=()    # 0 | 1
INSTALLED=()  # 0 | 1 (already present in target -> not selectable)

add_row() {
  # add_row <label> <type> <sub> <name> <src> <parent> <depth>
  LBL+=("$1"); TYPE+=("$2"); SUB+=("$3"); NAME+=("$4"); SRC+=("$5")
  PARENT+=("$6"); DEPTH+=("$7"); CHECKED+=(0); INSTALLED+=(0)
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
PROJECT_PATH=""
ASSUME_YES=0
DRY_RUN=0

usage() {
  cat <<EOF
${C_BOLD}ai-forge installer${C_RESET}

Usage: ./install.sh -p <project-path> [-y] [--dry-run]

  -p <path>     Target project path where skills/agents are installed.
  -y            Assume "yes" for confirmation prompts.
  -n, --dry-run Preview the actions without writing anything or running commands.
  -h            Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--path) PROJECT_PATH="${2:-}"; shift 2 ;;
    -p=*|--path=*) PROJECT_PATH="${1#*=}"; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use -h for help)" ;;
  esac
done

# -----------------------------------------------------------------------------
# 1. Resolve and validate the project path
# -----------------------------------------------------------------------------
if [ -z "$PROJECT_PATH" ]; then
  if [ -t 0 ]; then
    printf '%s' "${C_BOLD}Enter the target project path:${C_RESET} "
    IFS= read -r PROJECT_PATH
  fi
fi

[ -n "$PROJECT_PATH" ] || die "No project path provided. Re-run with -p <path>. Nothing to install."

# Expand a leading ~ to $HOME.
case "$PROJECT_PATH" in
  "~"|"~/"*) PROJECT_PATH="${HOME}/${PROJECT_PATH#\~/}" ;;
esac

[ -d "$PROJECT_PATH" ] || die "Project path does not exist or is not a directory: $PROJECT_PATH"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"   # normalize to absolute

[ "$PROJECT_PATH" != "$SCRIPT_DIR" ] || die "Target project must be different from the ai-forge repo itself."

info "Target project: ${C_BOLD}${PROJECT_PATH}${C_RESET}"
[ "$DRY_RUN" -eq 1 ] && dry "DRY-RUN MODE — no files will be written and no commands will be executed."

SKILLS_DEST="${PROJECT_PATH}/.agents/skills"
AGENTS_DEST="${PROJECT_PATH}/.agents/agents"

# -----------------------------------------------------------------------------
# Helpers to detect "already installed" items
# -----------------------------------------------------------------------------
skill_installed() { [ -f "${SKILLS_DEST}/$1/SKILL.md" ]; }
agent_installed() { [ -f "${AGENTS_DEST}/$1.md" ]; }

# Extract the first fenced code block of a given language from a markdown file.
# Usage: extract_code_block <file> <lang>
extract_code_block() {
  local file="$1" lang="$2"
  [ -f "$file" ] || return 0
  awk -v lang="$lang" '
    $0 == "```" lang { grab=1; next }
    grab && $0 == "```" { exit }
    grab { print }
  ' "$file"
}

# -----------------------------------------------------------------------------
# 2. Build the installable item tree
# -----------------------------------------------------------------------------
build_items() {
  local sub subdir name file dir parent_idx

  # ---- Agents -------------------------------------------------------------
  add_row "Agents" "cat" "" "" "" "-1" 0
  local agents_cat_idx=$(( ${#LBL[@]} - 1 ))

  if [ -d "${SCRIPT_DIR}/agents" ]; then
    while IFS= read -r subdir; do
      [ -n "$subdir" ] || continue
      sub="$(basename "$subdir")"
      # Only add the subfolder if it actually contains .md agent files.
      local has_agent=0
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        has_agent=1; break
      done < <(find "$subdir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
      [ "$has_agent" -eq 1 ] || continue

      add_row "$sub" "sub" "$sub" "" "$subdir" "$agents_cat_idx" 1
      parent_idx=$(( ${#LBL[@]} - 1 ))

      while IFS= read -r file; do
        [ -n "$file" ] || continue
        name="$(basename "$file" .md)"
        add_row "$name" "agent" "$sub" "$name" "$file" "$parent_idx" 2
        if agent_installed "$name"; then INSTALLED[$(( ${#LBL[@]} - 1 ))]=1; fi
      done < <(find "$subdir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
    done < <(find "${SCRIPT_DIR}/agents" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  fi

  # ---- Skills -------------------------------------------------------------
  add_row "Skills" "cat" "" "" "" "-1" 0
  local skills_cat_idx=$(( ${#LBL[@]} - 1 ))

  if [ -d "${SCRIPT_DIR}/skills" ]; then
    while IFS= read -r subdir; do
      [ -n "$subdir" ] || continue
      sub="$(basename "$subdir")"

      # Collect skill directories (those containing a SKILL.md) under this sub.
      local skill_dirs=()
      while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        skill_dirs+=("$dir")
      done < <(find "$subdir" -type f -name 'SKILL.md' -exec dirname {} \; 2>/dev/null | sort -u)

      if [ "${#skill_dirs[@]}" -gt 0 ]; then
        # Normal subfolder with one or more SKILL.md leaves.
        add_row "$sub" "sub" "$sub" "" "$subdir" "$skills_cat_idx" 1
        parent_idx=$(( ${#LBL[@]} - 1 ))
        local sd
        for sd in "${skill_dirs[@]}"; do
          name="$(basename "$sd")"
          add_row "$name" "skill" "$sub" "$name" "$sd" "$parent_idx" 2
          if skill_installed "$name"; then INSTALLED[$(( ${#LBL[@]} - 1 ))]=1; fi
        done
      elif [ -f "${subdir}/README.md" ]; then
        # "Remote" skill bundle installed via a README command (e.g. angular).
        add_row "$sub ${C_DIM}(via README command)${C_RESET}" "readme" "$sub" "$sub" "$subdir" "$skills_cat_idx" 1
      fi
    done < <(find "${SCRIPT_DIR}/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  fi

  # ---- Helper commands ----------------------------------------------------
  add_row "Run \`auto-skills\` on the project (npx autoskills)" "cmd" "" "auto-skills" "" "-1" 0

  # Show recommendation scanners only when the relevant config exists in the
  # target project (per install.md).
  if [ -d "${PROJECT_PATH}/.cursor" ] || [ -f "${PROJECT_PATH}/CLAUDE.md" ]; then
    add_row "Scan Cursor recommendations (agent automation-recommender)" "cmd" "" "scan-cursor-recommendations" "" "-1" 0
  fi
  if [ -d "${PROJECT_PATH}/.claude" ] || [ -f "${PROJECT_PATH}/CLAUDE.md" ]; then
    add_row "Scan Claude recommendations (claude automation-recommender)" "cmd" "" "scan-claude-recommendations" "" "-1" 0
  fi
}

build_items
[ "${#LBL[@]}" -gt 0 ] || die "No installable items found in ${SCRIPT_DIR}."

# -----------------------------------------------------------------------------
# 3. Interactive checkbox menu (arrow keys + spacebar)
# -----------------------------------------------------------------------------

# Is row $1 a descendant of row $2?
is_descendant() {
  local cur="${PARENT[$1]}" anc="$2"
  while [ "$cur" -ge 0 ] 2>/dev/null; do
    [ "$cur" -eq "$anc" ] && return 0
    cur="${PARENT[$cur]}"
  done
  return 1
}

# Set row $1 (and all its descendants) to checked-state $2, skipping installed.
toggle_subtree() {
  local idx="$1" val="$2" j
  [ "${INSTALLED[$idx]}" = "1" ] || CHECKED[$idx]="$val"
  for (( j=0; j<${#LBL[@]}; j++ )); do
    if [ "${INSTALLED[$j]}" = "0" ] && is_descendant "$j" "$idx"; then
      CHECKED[$j]="$val"
    fi
  done
}

# Recompute cat/sub checkmarks based on their children (cosmetic aggregation).
recompute_parents() {
  local i j has_child all_checked
  for (( i=${#LBL[@]}-1; i>=0; i-- )); do
    case "${TYPE[$i]}" in
      cat|sub)
        has_child=0; all_checked=1
        for (( j=0; j<${#LBL[@]}; j++ )); do
          if [ "${PARENT[$j]}" = "$i" ]; then
            has_child=1
            if [ "${INSTALLED[$j]}" = "1" ]; then
              :   # installed children count as satisfied
            elif [ "${CHECKED[$j]}" = "0" ]; then
              all_checked=0
            fi
          fi
        done
        if [ "$has_child" = "1" ] && [ "$all_checked" = "1" ]; then
          CHECKED[$i]=1
        else
          CHECKED[$i]=0
        fi
        ;;
    esac
  done
}

# Top row of the scrolling viewport; persists across renders.
VP_TOP=0

render_menu() {
  local cursor="$1" i indent box mark line
  local rows cols visible total last maxtop path_disp maxpath

  # Detect terminal size (fall back to a sane default if unavailable).
  rows="$(tput lines 2>/dev/null || echo "${LINES:-24}")"
  cols="$(tput cols  2>/dev/null || echo "${COLUMNS:-80}")"
  case "$rows" in (*[!0-9]*|'') rows=24 ;; esac
  case "$cols" in (*[!0-9]*|'') cols=80 ;; esac

  total=${#LBL[@]}
  # Reserve lines for the title, hint, position bar, bottom indicator and a
  # one-line safety margin (so the final newline never forces a scroll).
  visible=$(( rows - 5 ))
  [ "$visible" -lt 3 ] && visible=3
  [ "$visible" -gt "$total" ] && visible=$total

  # Scroll the viewport so the cursor is always inside it.
  [ "$cursor" -lt "$VP_TOP" ] && VP_TOP=$cursor
  [ "$cursor" -ge $(( VP_TOP + visible )) ] && VP_TOP=$(( cursor - visible + 1 ))
  maxtop=$(( total - visible )); [ "$maxtop" -lt 0 ] && maxtop=0
  [ "$VP_TOP" -gt "$maxtop" ] && VP_TOP=$maxtop
  [ "$VP_TOP" -lt 0 ] && VP_TOP=0
  last=$(( VP_TOP + visible - 1 )); [ "$last" -ge "$total" ] && last=$(( total - 1 ))

  printf '\033[H\033[J'   # clear screen, home cursor

  # Header — truncate the target path so it never wraps and offsets the layout.
  path_disp="$PROJECT_PATH"
  maxpath=$(( cols - 22 )); [ "$maxpath" -lt 10 ] && maxpath=10
  if [ "${#path_disp}" -gt "$maxpath" ]; then
    path_disp="…${path_disp: -$(( maxpath - 1 ))}"
  fi
  printf '%s\n' "${C_BOLD}ai-forge installer${C_RESET} — ${C_CYAN}${path_disp}${C_RESET}"
  printf '%s\n' "${C_DIM}↑/↓ move · space toggle · a all · n none · enter confirm · q quit${C_RESET}"

  # Position bar (+ "more above" hint when scrolled).
  if [ "$VP_TOP" -gt 0 ]; then
    printf '%s\n' "${C_DIM}  [$(( cursor + 1 ))/${total}]  ▲ more above${C_RESET}"
  else
    printf '%s\n' "${C_DIM}  [$(( cursor + 1 ))/${total}]${C_RESET}"
  fi

  for (( i=VP_TOP; i<=last; i++ )); do
    indent=""
    case "${DEPTH[$i]}" in
      1) indent="  " ;;
      2) indent="    " ;;
    esac

    if [ "${INSTALLED[$i]}" = "1" ]; then
      box="${C_GREEN}[✓]${C_RESET}"
      mark=" ${C_DIM}(installed)${C_RESET}"
    else
      if [ "${CHECKED[$i]}" = "1" ]; then
        box="${C_GREEN}[x]${C_RESET}"
      else
        box="[ ]"
      fi
      mark=""
    fi

    line="${box} ${indent}${LBL[$i]}${mark}"
    if [ "$i" -eq "$cursor" ]; then
      printf '%s\n' "${C_BLUE}❯${C_RESET} ${line}"
    else
      printf '%s\n' "  ${line}"
    fi
  done

  # Bottom "more below" hint (always emit a line to keep the layout stable).
  if [ "$last" -lt $(( total - 1 )) ]; then
    printf '%s\n' "${C_DIM}  ▼ more below${C_RESET}"
  else
    printf '\n'
  fi
}

run_menu() {
  [ -t 0 ] || die "Interactive menu requires a TTY. Run the script directly in a terminal."

  local cursor=0 key key2 i
  VP_TOP=0
  while :; do
    recompute_parents
    render_menu "$cursor"

    IFS= read -rsn1 key || break
    if [ "$key" = $'\033' ]; then
      read -rsn2 -t 0.001 key2
      key="${key}${key2}"
    fi

    case "$key" in
      $'\033[A'|k)  # up
        cursor=$(( cursor - 1 )); [ "$cursor" -lt 0 ] && cursor=$(( ${#LBL[@]} - 1 )) ;;
      $'\033[B'|j)  # down
        cursor=$(( cursor + 1 )); [ "$cursor" -ge "${#LBL[@]}" ] && cursor=0 ;;
      ' ')          # toggle
        if [ "${INSTALLED[$cursor]}" = "1" ]; then
          :
        else
          if [ "${CHECKED[$cursor]}" = "1" ]; then
            toggle_subtree "$cursor" 0
          else
            toggle_subtree "$cursor" 1
          fi
        fi ;;
      a|A)          # select all
        for (( i=0; i<${#LBL[@]}; i++ )); do
          [ "${INSTALLED[$i]}" = "0" ] && CHECKED[$i]=1
        done ;;
      n|N)          # select none
        for (( i=0; i<${#LBL[@]}; i++ )); do CHECKED[$i]=0; done ;;
      ''|$'\n'|$'\r')   # enter -> confirm
        break ;;
      q|Q)
        printf '\033[H\033[J'
        die "Installation cancelled." ;;
    esac
  done
  printf '\033[H\033[J'
}

run_menu

# -----------------------------------------------------------------------------
# 4. Resolve selection -> concrete install actions
# -----------------------------------------------------------------------------
SEL_SKILL_NAME=(); SEL_SKILL_SRC=(); SEL_SKILL_SUB=()
SEL_AGENT_NAME=(); SEL_AGENT_SRC=()
SEL_README_NAME=(); SEL_README_SRC=()
SEL_CMD=()

for (( i=0; i<${#LBL[@]}; i++ )); do
  [ "${CHECKED[$i]}" = "1" ] || continue
  [ "${INSTALLED[$i]}" = "0" ] || continue
  case "${TYPE[$i]}" in
    skill)  SEL_SKILL_NAME+=("${NAME[$i]}"); SEL_SKILL_SRC+=("${SRC[$i]}"); SEL_SKILL_SUB+=("${SUB[$i]}") ;;
    agent)  SEL_AGENT_NAME+=("${NAME[$i]}"); SEL_AGENT_SRC+=("${SRC[$i]}") ;;
    readme) SEL_README_NAME+=("${NAME[$i]}"); SEL_README_SRC+=("${SRC[$i]}") ;;
    cmd)    SEL_CMD+=("${NAME[$i]}") ;;
  esac
done

total_selected=$(( ${#SEL_SKILL_NAME[@]} + ${#SEL_AGENT_NAME[@]} + ${#SEL_README_NAME[@]} + ${#SEL_CMD[@]} ))
[ "$total_selected" -gt 0 ] || die "Nothing selected. Exiting."

# -----------------------------------------------------------------------------
# 5. Dependency resolution
# -----------------------------------------------------------------------------
# Declare skill -> "dep1 dep2" relationships here as the catalog grows.
# (Currently no hard dependencies are defined; the engine below enforces any
# that you add.)
deps_for() {
  case "$1" in
    # example) echo "git-workflow" ;;
    *) echo "" ;;
  esac
}

is_skill_selected() {
  local target="$1" s
  for s in "${SEL_SKILL_NAME[@]:-}"; do [ "$s" = "$target" ] && return 0; done
  return 1
}

# Items whose dependencies are missing get dropped (with confirmation).
DROP_NAMES=()
check_dependencies() {
  local idx name dep missing
  local kept_name=() kept_src=() kept_sub=()
  for idx in "${!SEL_SKILL_NAME[@]}"; do
    name="${SEL_SKILL_NAME[$idx]}"
    missing=""
    for dep in $(deps_for "$name"); do
      if ! is_skill_selected "$dep" && ! skill_installed "$dep"; then
        missing="${missing} ${dep}"
      fi
    done
    if [ -n "$missing" ]; then
      warn "Skill '${name}' is missing dependencies:${missing}"
      DROP_NAMES+=("$name")
    else
      kept_name+=("$name"); kept_src+=("${SEL_SKILL_SRC[$idx]}"); kept_sub+=("${SEL_SKILL_SUB[$idx]}")
    fi
  done

  if [ "${#DROP_NAMES[@]}" -gt 0 ]; then
    local ans="y"
    if [ "$ASSUME_YES" -eq 0 ]; then
      printf '%s' "${C_YELLOW}Continue and skip the items above? [y/N]${C_RESET} "
      IFS= read -r ans
    fi
    case "$ans" in
      y|Y|yes|YES) SEL_SKILL_NAME=("${kept_name[@]:-}"); SEL_SKILL_SRC=("${kept_src[@]:-}"); SEL_SKILL_SUB=("${kept_sub[@]:-}")
                   # Strip the empty placeholder if arrays ended up empty.
                   [ "${#kept_name[@]}" -eq 0 ] && SEL_SKILL_NAME=() && SEL_SKILL_SRC=() && SEL_SKILL_SUB=() ;;
      *) die "Aborted due to unmet dependencies." ;;
    esac
  fi
}
check_dependencies

# -----------------------------------------------------------------------------
# 5b. External command (system tool) dependencies
# -----------------------------------------------------------------------------
# Maps a selected item to the external CLI command(s) it expects to be on the
# PATH. These are reported in the summary table only -- this installer never
# installs system tools (out of scope).
#
# Key format:
#   * skills / readme skills -> "<subfolder>/<name>"
#   * agents                 -> "agent/<name>"
#
# A token may list interchangeable alternatives separated by "|"
# (e.g. "gh|glab" = satisfied if EITHER is available).
cmd_deps_for() {
  case "$1" in
    common/context7-cli)                                echo "ctx7" ;;
    common/gh)                                          echo "gh" ;;
    common/glab)                                        echo "glab" ;;
    common/git-workflow)                                echo "git" ;;
    common/create-mr-pr)                                echo "git gh|glab" ;;
    python/pytest)                                      echo "python3|python pytest" ;;
    hexagonal-architecture/create-alembic-migration)    echo "python3|python alembic|poetry|uv|pdm" ;;
    hexagonal-architecture/testing)                     echo "python3|python pytest|poetry|uv" ;;
    playwright/playwright-cli)                           echo "playwright-cli|playwright" ;;
    agent/mr-pr-reviewer)                               echo "git gh|glab" ;;
    *)                                                  echo "" ;;
  esac
}

# Parallel arrays holding the rendered dependency table rows.
DEP_ROW_ITEM=()
DEP_ROW_REQ=()
DEP_ROW_OK=()       # 1 = available, 0 = missing
DEP_ROW_FOUND=()    # which concrete binary satisfied the requirement
DEP_MISSING_COUNT=0

# Resolve a single token (possibly "a|b|c") into requirement display + status.
# Sets the RT_* globals.
resolve_token() {
  local tok="$1" alt found=""
  case "$tok" in
    *"|"*)
      local OLD_IFS="$IFS"; IFS='|'
      for alt in $tok; do
        if command -v "$alt" >/dev/null 2>&1; then found="$alt"; break; fi
      done
      IFS="$OLD_IFS"
      RT_REQ="${tok//|/ or }"
      ;;
    *)
      RT_REQ="$tok"
      command -v "$tok" >/dev/null 2>&1 && found="$tok"
      ;;
  esac
  if [ -n "$found" ]; then RT_OK=1; RT_FOUND="$found"; else RT_OK=0; RT_FOUND=""; fi
}

# Append one row per required token for a given item label.
add_dependency_rows() {
  local label="$1" toks="$2" t
  [ -n "$toks" ] || return 0
  for t in $toks; do
    resolve_token "$t"
    DEP_ROW_ITEM+=("$label")
    DEP_ROW_REQ+=("$RT_REQ")
    DEP_ROW_OK+=("$RT_OK")
    DEP_ROW_FOUND+=("$RT_FOUND")
    [ "$RT_OK" -eq 0 ] && DEP_MISSING_COUNT=$(( DEP_MISSING_COUNT + 1 ))
  done
}

build_dependency_table() {
  local i
  for i in "${!SEL_SKILL_NAME[@]}"; do
    [ -n "${SEL_SKILL_NAME[$i]:-}" ] || continue
    add_dependency_rows "${SEL_SKILL_NAME[$i]}" "$(cmd_deps_for "${SEL_SKILL_SUB[$i]}/${SEL_SKILL_NAME[$i]}")"
  done
  for i in "${!SEL_README_NAME[@]}"; do
    [ -n "${SEL_README_NAME[$i]:-}" ] || continue
    add_dependency_rows "${SEL_README_NAME[$i]}" "$(cmd_deps_for "${SEL_README_NAME[$i]}/${SEL_README_NAME[$i]}")"
  done
  for i in "${!SEL_AGENT_NAME[@]}"; do
    [ -n "${SEL_AGENT_NAME[$i]:-}" ] || continue
    add_dependency_rows "${SEL_AGENT_NAME[$i]}" "$(cmd_deps_for "agent/${SEL_AGENT_NAME[$i]}")"
  done
}

# Render the dependency table (aligned columns, colored status).
print_dependency_table() {
  [ "${#DEP_ROW_ITEM[@]}" -gt 0 ] || return 0
  local i w_item=4 w_req=7 status

  for i in "${!DEP_ROW_ITEM[@]}"; do
    [ "${#DEP_ROW_ITEM[$i]}" -gt "$w_item" ] && w_item="${#DEP_ROW_ITEM[$i]}"
    [ "${#DEP_ROW_REQ[$i]}"  -gt "$w_req"  ] && w_req="${#DEP_ROW_REQ[$i]}"
  done

  printf '\n%s\n' "${C_BOLD}External command dependencies:${C_RESET}"
  printf '%s\n'   "${C_DIM}(not installed by this script — install any missing tools yourself)${C_RESET}"
  printf '  %-*s  %-*s  %s\n' "$w_item" "Item" "$w_req" "Command" "Status"
  printf '  %-*s  %-*s  %s\n' "$w_item" "$(printf '%.0s-' $(seq 1 "$w_item"))" \
                              "$w_req"  "$(printf '%.0s-' $(seq 1 "$w_req"))"  "------"

  for i in "${!DEP_ROW_ITEM[@]}"; do
    if [ "${DEP_ROW_OK[$i]}" -eq 1 ]; then
      status="${C_GREEN}✓ available (${DEP_ROW_FOUND[$i]})${C_RESET}"
    else
      status="${C_RED}✗ missing${C_RESET}"
    fi
    printf '  %-*s  %-*s  %b\n' "$w_item" "${DEP_ROW_ITEM[$i]}" "$w_req" "${DEP_ROW_REQ[$i]}" "$status"
  done

  if [ "$DEP_MISSING_COUNT" -gt 0 ]; then
    printf '%s\n' "${C_YELLOW}${DEP_MISSING_COUNT} command(s) missing.${C_RESET} Install them before using the affected skills/agents."
  fi
}

build_dependency_table

# -----------------------------------------------------------------------------
# 5c. MCP server dependencies
# -----------------------------------------------------------------------------
# Maps a selected item to the MCP server(s) it relies on. These are reported in
# the summary only -- the installer does not configure MCP servers. Use the
# repo's assets/MCPs/.mcp.json as a starting template.
#
# Key format matches cmd_deps_for (skills: "<sub>/<name>", agents: "agent/<n>").
# A token may carry an optional "(fallback)" suffix to mark non-critical use.
mcp_deps_for() {
  case "$1" in
    chrome/chrome-devtools)              echo "chrome-devtools" ;;
    astro/astro)                         echo "astro-docs" ;;
    common/context7-cli)                 echo "context7(fallback)" ;;
    playwright/webapp-testing)           echo "playwright(fallback)" ;;
    playwright/e2e-testing)              echo "playwright(fallback)" ;;
    playwright/web-design-reviewer)      echo "playwright(fallback)" ;;
    *)                                   echo "" ;;
  esac
}

# MCP config files that may declare servers in the target project.
mcp_config_files() {
  printf '%s\n' \
    "${PROJECT_PATH}/.mcp.json" \
    "${PROJECT_PATH}/.cursor/mcp.json" \
    "${PROJECT_PATH}/.agents/mcp/mcp.json"
}

# Best-effort check: is an MCP server name referenced in any project config?
# Echoes the file it was found in (and returns 0) or returns 1 when absent.
mcp_configured() {
  local name="$1" f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if grep -q "\"${name}\"" "$f" 2>/dev/null; then
      printf '%s' "$f"; return 0
    fi
  done < <(mcp_config_files)
  return 1
}

MCP_ROW_ITEM=()
MCP_ROW_SERVER=()
MCP_ROW_OK=()       # 1 = configured, 0 = not found
MCP_ROW_NOTE=()     # "" | "fallback"
MCP_MISSING_COUNT=0

add_mcp_rows() {
  local label="$1" toks="$2" t server note where
  [ -n "$toks" ] || return 0
  for t in $toks; do
    note=""
    case "$t" in *"(fallback)") note="fallback"; server="${t%%(*}" ;; *) server="$t" ;; esac
    MCP_ROW_ITEM+=("$label")
    MCP_ROW_SERVER+=("$server")
    MCP_ROW_NOTE+=("$note")
    if where="$(mcp_configured "$server")"; then
      MCP_ROW_OK+=("1")
    else
      MCP_ROW_OK+=("0")
      MCP_MISSING_COUNT=$(( MCP_MISSING_COUNT + 1 ))
    fi
  done
}

build_mcp_table() {
  local i
  for i in "${!SEL_SKILL_NAME[@]}"; do
    [ -n "${SEL_SKILL_NAME[$i]:-}" ] || continue
    add_mcp_rows "${SEL_SKILL_NAME[$i]}" "$(mcp_deps_for "${SEL_SKILL_SUB[$i]}/${SEL_SKILL_NAME[$i]}")"
  done
  for i in "${!SEL_README_NAME[@]}"; do
    [ -n "${SEL_README_NAME[$i]:-}" ] || continue
    add_mcp_rows "${SEL_README_NAME[$i]}" "$(mcp_deps_for "${SEL_README_NAME[$i]}/${SEL_README_NAME[$i]}")"
  done
  for i in "${!SEL_AGENT_NAME[@]}"; do
    [ -n "${SEL_AGENT_NAME[$i]:-}" ] || continue
    add_mcp_rows "${SEL_AGENT_NAME[$i]}" "$(mcp_deps_for "agent/${SEL_AGENT_NAME[$i]}")"
  done
}

print_mcp_table() {
  [ "${#MCP_ROW_ITEM[@]}" -gt 0 ] || return 0
  local i w_item=4 w_srv=10 status

  for i in "${!MCP_ROW_ITEM[@]}"; do
    [ "${#MCP_ROW_ITEM[$i]}"   -gt "$w_item" ] && w_item="${#MCP_ROW_ITEM[$i]}"
    [ "${#MCP_ROW_SERVER[$i]}" -gt "$w_srv"  ] && w_srv="${#MCP_ROW_SERVER[$i]}"
  done

  printf '\n%s\n' "${C_BOLD}MCP server dependencies:${C_RESET}"
  printf '%s\n'   "${C_DIM}(not configured by this script — see assets/MCPs/.mcp.json for a template)${C_RESET}"
  printf '  %-*s  %-*s  %s\n' "$w_item" "Item" "$w_srv" "MCP server" "Status"
  printf '  %-*s  %-*s  %s\n' "$w_item" "$(printf '%.0s-' $(seq 1 "$w_item"))" \
                              "$w_srv"  "$(printf '%.0s-' $(seq 1 "$w_srv"))"  "------"

  local note
  for i in "${!MCP_ROW_ITEM[@]}"; do
    if [ "${MCP_ROW_OK[$i]}" -eq 1 ]; then
      status="${C_GREEN}✓ configured${C_RESET}"
    else
      status="${C_YELLOW}● not configured${C_RESET}"
    fi
    note=""
    [ -n "${MCP_ROW_NOTE[$i]}" ] && note="  ${C_DIM}(${MCP_ROW_NOTE[$i]})${C_RESET}"
    printf '  %-*s  %-*s  %b%b\n' "$w_item" "${MCP_ROW_ITEM[$i]}" "$w_srv" "${MCP_ROW_SERVER[$i]}" "$status" "$note"
  done

  if [ "$MCP_MISSING_COUNT" -gt 0 ]; then
    printf '%s\n' "${C_YELLOW}${MCP_MISSING_COUNT} MCP server(s) not found${C_RESET} in the project's MCP config. Add them to use the affected skills."
  fi
}

build_mcp_table

# -----------------------------------------------------------------------------
# 6. Perform the installation
# -----------------------------------------------------------------------------
INSTALLED_SKILLS=()
INSTALLED_AGENTS=()
RAN_COMMANDS=()
SPECIAL_NOTES=()

install_skill() {
  # Copy the entire skill directory (so references/ and helpers come along)
  # into .agents/skills/<name>/.
  local name="$1" src="$2" dest="${SKILLS_DEST}/$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    dry "Would install skill: ${name} -> ${dest}/"
  else
    mkdir -p "$dest"
    cp -R "${src}/." "${dest}/"
    ok "Installed skill: ${name}"
  fi
  INSTALLED_SKILLS+=("$name")
}

install_agent() {
  local name="$1" src="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
    dry "Would install agent: ${name} -> ${AGENTS_DEST}/${name}.md"
  else
    mkdir -p "$AGENTS_DEST"
    cp "$src" "${AGENTS_DEST}/${name}.md"
    ok "Installed agent: ${name}"
  fi
  INSTALLED_AGENTS+=("$name")
}

install_readme_skill() {
  # README-driven (remote) skill, e.g. angular -> `npx skills add ...`.
  local name="$1" src="$2" cmd
  cmd="$(extract_code_block "${src}/README.md" bash | head -n 1)"
  if [ -z "$cmd" ]; then
    warn "No install command found in ${src}/README.md for '${name}'. Skipping."
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    dry "Would run README install for '${name}': ${cmd}"
    # The first token of the command is the binary it depends on.
    local bin="${cmd%% *}"
    command -v "$bin" >/dev/null 2>&1 || warn "'${bin}' not found; this step would fail on a real run."
    RAN_COMMANDS+=("${name}: ${cmd} (skipped: dry-run)")
    return 0
  fi
  info "Installing '${name}' via README command: ${C_BOLD}${cmd}${C_RESET}"
  ( cd "$PROJECT_PATH" && eval "$cmd" )
  if [ $? -eq 0 ]; then
    ok "Ran README install for: ${name}"
    RAN_COMMANDS+=("${name}: ${cmd}")
  else
    warn "README install command failed for '${name}'."
  fi
}

# Validate the output of a recommendation scan. Some CLIs (e.g. claude, agent)
# exit non-zero AND/OR write their error message into stdout, so a redirected
# file can look "generated" while actually containing an auth failure.
# On failure: keep the raw output as <file>.error.md, warn with a fix, and do
# NOT add a "review this file" note.
finalize_recommendation() {
  local label="$1" file="$2" rc="$3" hint="$4" path="${PROJECT_PATH}/$2"
  local failed=0

  [ "$rc" -ne 0 ] && failed=1
  if [ ! -s "$path" ]; then
    failed=1
  elif grep -qiE 'failed to authenticate|invalid authentication|not authenticated|unauthorized|api error:? *40[0-9]' "$path" 2>/dev/null; then
    failed=1
  fi

  if [ "$failed" -eq 1 ]; then
    local errfile="${file%.md}.error.md"
    [ -f "$path" ] && mv "$path" "${PROJECT_PATH}/${errfile}" 2>/dev/null
    warn "${label} failed (CLI exit ${rc}). This is usually an authentication problem."
    warn "  Fix: ${hint}"
    [ -f "${PROJECT_PATH}/${errfile}" ] && warn "  Raw output kept at ${PROJECT_PATH}/${errfile}"
    RAN_COMMANDS+=("${label}: FAILED — see ${errfile}")
    return 1
  fi

  RAN_COMMANDS+=("${label}: ${file} generated")
  SPECIAL_NOTES+=("Review ${path} and re-run install.sh for any suggested skills.")
  return 0
}

run_helper_command() {
  local id="$1" rc
  case "$id" in
    auto-skills)
      if [ "$DRY_RUN" -eq 1 ]; then
        dry "Would run in ${PROJECT_PATH}: npx autoskills"
        command -v npx >/dev/null 2>&1 || warn "npx not found; this step would be skipped on a real run."
        RAN_COMMANDS+=("auto-skills: npx autoskills (skipped: dry-run)"); return 0
      fi
      if ! command -v npx >/dev/null 2>&1; then
        warn "npx not found; cannot run autoskills. Install Node.js >= 22."; return 0
      fi
      info "Running autoskills in ${PROJECT_PATH} ..."
      ( cd "$PROJECT_PATH" && npx autoskills )
      RAN_COMMANDS+=("auto-skills: npx autoskills")
      ;;
    scan-cursor-recommendations)
      if [ "$DRY_RUN" -eq 1 ]; then
        dry "Would run in ${PROJECT_PATH}: agent -p <claude-automation-recommender> > cursor-recommendations.md"
        command -v agent >/dev/null 2>&1 || warn "'agent' CLI not found; this step would be skipped on a real run."
        RAN_COMMANDS+=("scan-cursor: cursor-recommendations.md (skipped: dry-run)"); return 0
      fi
      if ! command -v agent >/dev/null 2>&1; then
        warn "'agent' CLI not found; skipping Cursor recommendations scan."; return 0
      fi
      info "Scanning Cursor recommendations -> cursor-recommendations.md"
      ( cd "$PROJECT_PATH" && agent -p "$(cat "${SCRIPT_DIR}/.agents/skills/claude-automation-recommender/SKILL.md" 2>/dev/null || echo '/claude-automation-recommender')" --output-format text > cursor-recommendations.md ); rc=$?
      finalize_recommendation "scan-cursor" "cursor-recommendations.md" "$rc" \
        "authenticate the Cursor agent CLI (run 'agent login'), then re-run."
      ;;
    scan-claude-recommendations)
      if [ "$DRY_RUN" -eq 1 ]; then
        dry "Would run in ${PROJECT_PATH}: claude -p \"/claude-automation-recommender\" > claude-recommendations.md"
        command -v claude >/dev/null 2>&1 || warn "'claude' CLI not found; this step would be skipped on a real run."
        RAN_COMMANDS+=("scan-claude: claude-recommendations.md (skipped: dry-run)"); return 0
      fi
      if ! command -v claude >/dev/null 2>&1; then
        warn "'claude' CLI not found; skipping Claude recommendations scan."; return 0
      fi
      info "Scanning Claude recommendations -> claude-recommendations.md"
      ( cd "$PROJECT_PATH" && claude -p "/claude-automation-recommender" --output-format text > claude-recommendations.md ); rc=$?
      finalize_recommendation "scan-claude" "claude-recommendations.md" "$rc" \
        "authenticate the Claude CLI (run 'claude login', or set a valid ANTHROPIC_API_KEY), then re-run."
      ;;
  esac
}

if [ "$DRY_RUN" -eq 1 ]; then
  dry "Previewing installation (no changes will be made) ..."
else
  info "Starting installation ..."
fi

# Agents
for idx in "${!SEL_AGENT_NAME[@]}"; do
  [ -n "${SEL_AGENT_NAME[$idx]}" ] || continue
  install_agent "${SEL_AGENT_NAME[$idx]}" "${SEL_AGENT_SRC[$idx]}"
done

# Skills (copy SKILL.md bundles)
for idx in "${!SEL_SKILL_NAME[@]}"; do
  [ -n "${SEL_SKILL_NAME[$idx]}" ] || continue
  install_skill "${SEL_SKILL_NAME[$idx]}" "${SEL_SKILL_SRC[$idx]}"
done

# README-driven (remote) skills
for idx in "${!SEL_README_NAME[@]}"; do
  [ -n "${SEL_README_NAME[$idx]:-}" ] || continue
  install_readme_skill "${SEL_README_NAME[$idx]}" "${SEL_README_SRC[$idx]}"
done

# Helper commands (run sequentially; each waits for the previous to finish)
for idx in "${!SEL_CMD[@]}"; do
  [ -n "${SEL_CMD[$idx]:-}" ] || continue
  run_helper_command "${SEL_CMD[$idx]}"
done

# -----------------------------------------------------------------------------
# 7. Collect subfolder README post-install prompts (e.g. hexagonal-architecture)
# -----------------------------------------------------------------------------
seen_subs=" "
for idx in "${!SEL_SKILL_SUB[@]}"; do
  sub="${SEL_SKILL_SUB[$idx]}"
  [ -n "$sub" ] || continue
  case "$seen_subs" in *" $sub "*) continue ;; esac
  seen_subs="${seen_subs}${sub} "
  readme="${SCRIPT_DIR}/skills/${sub}/README.md"
  if [ -f "$readme" ]; then
    prompt="$(extract_code_block "$readme" markdown)"
    if [ -n "$prompt" ]; then
      SPECIAL_NOTES+=("Post-install prompt for '${sub}' (from skills/${sub}/README.md):
${prompt}")
    fi
  fi
done

# -----------------------------------------------------------------------------
# 8. Copy AGENTS.template.md -> project AGENTS.md
# -----------------------------------------------------------------------------
AGENTS_MD_COPIED=0
if [ -f "${SCRIPT_DIR}/AGENTS.template.md" ]; then
  dest="${PROJECT_PATH}/AGENTS.md"
  if [ "$DRY_RUN" -eq 1 ]; then
    [ -f "$dest" ] && dry "Would back up existing AGENTS.md -> AGENTS.md.bak"
    dry "Would copy AGENTS.template.md -> ${dest}"
    AGENTS_MD_COPIED=1
  else
    if [ -f "$dest" ]; then
      cp "$dest" "${dest}.bak"
      warn "Existing AGENTS.md backed up to AGENTS.md.bak"
    fi
    cp "${SCRIPT_DIR}/AGENTS.template.md" "$dest"
    ok "Copied AGENTS.template.md -> AGENTS.md"
    AGENTS_MD_COPIED=1
  fi
else
  warn "AGENTS.template.md not found in repo; skipped AGENTS.md creation."
fi

# -----------------------------------------------------------------------------
# 9. Summary
# -----------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  _verb="would be installed"
  printf '\n%s\n' "${C_BOLD}═════════════════ Installation summary (dry-run) ═════════════════${C_RESET}"
else
  _verb="installed"
  printf '\n%s\n' "${C_BOLD}════════════════════ Installation summary ════════════════════${C_RESET}"
fi
printf '%s\n'   "Target project: ${C_CYAN}${PROJECT_PATH}${C_RESET}"

if [ "${#INSTALLED_AGENTS[@]}" -gt 0 ]; then
  printf '\n%s\n' "${C_BOLD}Agents ${_verb} (-> .agents/agents/):${C_RESET}"
  for a in "${INSTALLED_AGENTS[@]}"; do printf '  • %s\n' "$a"; done
fi

if [ "${#INSTALLED_SKILLS[@]}" -gt 0 ]; then
  printf '\n%s\n' "${C_BOLD}Skills ${_verb} (-> .agents/skills/):${C_RESET}"
  for s in "${INSTALLED_SKILLS[@]}"; do printf '  • %s\n' "$s"; done
fi

if [ "${#RAN_COMMANDS[@]}" -gt 0 ]; then
  printf '\n%s\n' "${C_BOLD}Commands run:${C_RESET}"
  for c in "${RAN_COMMANDS[@]}"; do printf '  • %s\n' "$c"; done
fi

if [ "${#DROP_NAMES[@]}" -gt 0 ]; then
  printf '\n%s\n' "${C_YELLOW}Skipped (unmet dependencies):${C_RESET}"
  for d in "${DROP_NAMES[@]}"; do printf '  • %s\n' "$d"; done
fi

# External command dependencies (system tools the selected items expect).
print_dependency_table

# MCP server dependencies (MCP servers the selected items rely on).
print_mcp_table

# sync-ai recommendation
if is_skill_selected "sync-ai"; then
  printf '\n%s\n' "${C_YELLOW}Recommended:${C_RESET} run the ${C_BOLD}sync-ai${C_RESET} skill now to sync AI context files across your tools."
fi

# Special README notes (hexagonal prompt, scan recommendations, etc.)
if [ "${#SPECIAL_NOTES[@]}" -gt 0 ]; then
  for note in "${SPECIAL_NOTES[@]}"; do
    printf '\n%s\n' "${C_BOLD}Note:${C_RESET}"
    printf '%s\n' "$note"
  done
fi

# AGENTS.md adapt instruction
if [ "$AGENTS_MD_COPIED" -eq 1 ]; then
  cat <<EOF

${C_BOLD}Next step — adapt AGENTS.md${C_RESET}
From your Agent (Claude, Gemini, etc.), run the following prompt to adapt the \`AGENTS.md\` file:

  ${C_CYAN}> From the \`AGENTS.md\` file, review it and do the instruction on the \`TODO\` sections.${C_RESET}
EOF
fi

if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n%s\n' "${C_CYAN}${C_BOLD}Dry-run complete.${C_RESET} Re-run without ${C_BOLD}--dry-run${C_RESET} to apply these changes."
else
  printf '\n%s\n' "${C_GREEN}${C_BOLD}Done.${C_RESET}"
fi
