#!/usr/bin/env bash
#
# Installer parity check
# -----------------------------------------------------------------------------
# Installs everything twice -- once with install.sh, once with install.ps1 --
# into two throwaway projects and asserts the results are identical.
#
# The two installers are maintained by hand, so this is the guard that keeps
# them from drifting. Run it locally before touching either one:
#
#   ./tests/parity/compare-installers.sh
#
# Requirements: bash and pwsh (PowerShell 7+). Remote bundles are intentionally
# excluded from --list-all, so this check does not execute network commands.
# -----------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
SH_TARGET="${WORK_DIR}/from-bash"
PS_TARGET="${WORK_DIR}/from-powershell"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

fail() { printf '\n[parity] FAILED: %s\n' "$*" >&2; exit 1; }
step() { printf '\n[parity] %s\n' "$*"; }

command -v pwsh >/dev/null 2>&1 || fail "pwsh not found; install PowerShell 7+ to run the parity check."

mkdir -p "$SH_TARGET" "$PS_TARGET"

step "Installing with install.sh -> ${SH_TARGET}"
"${REPO_ROOT}/install.sh" -p "$SH_TARGET" --list-all -y > "${WORK_DIR}/bash.log" 2>&1 ||
  fail "install.sh exited non-zero (see ${WORK_DIR}/bash.log)"

step "Installing with install.ps1 -> ${PS_TARGET}"
pwsh -NoProfile -File "${REPO_ROOT}/install.ps1" -Path "$PS_TARGET" -ListAll -Yes -NoColor > "${WORK_DIR}/pwsh.log" 2>&1 ||
  fail "install.ps1 exited non-zero (see ${WORK_DIR}/pwsh.log)"

step "Comparing the installed file trees"
( cd "$SH_TARGET" && find . -type f | sort ) > "${WORK_DIR}/bash.files"
( cd "$PS_TARGET" && find . -type f | sort ) > "${WORK_DIR}/pwsh.files"
diff -u "${WORK_DIR}/bash.files" "${WORK_DIR}/pwsh.files" || fail "the installers produced different file trees"

step "Comparing file contents"
diff -r --exclude manifest.json "$SH_TARGET" "$PS_TARGET" || fail "installed files differ in content"

step "Comparing install manifests"
# generatedAt and the absolute target/root paths legitimately differ; the
# recorded inventory must not.
normalize_manifest() {
  if command -v jq >/dev/null 2>&1; then
    jq -S '{schema, skills, agents, remoteSkills, commands}' "$1"
  else
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({k:d[k] for k in ("schema","skills","agents","remoteSkills","commands")}, sort_keys=True, indent=2))' "$1"
  fi
}
normalize_manifest "${SH_TARGET}/.agents/manifest.json" > "${WORK_DIR}/bash.manifest"
normalize_manifest "${PS_TARGET}/.agents/manifest.json" > "${WORK_DIR}/pwsh.manifest"
diff -u "${WORK_DIR}/bash.manifest" "${WORK_DIR}/pwsh.manifest" || fail "install manifests differ"

step "Comparing the selection count of a second (idempotent) run"
sh_count="$("${REPO_ROOT}/install.sh" -p "$SH_TARGET" --list-all --dry-run 2>&1 | sed -n 's/.*selected \([0-9]*\) skill.*/\1/p' | head -n 1)"
ps_count="$(pwsh -NoProfile -File "${REPO_ROOT}/install.ps1" -Path "$PS_TARGET" -ListAll -DryRun -NoColor 2>&1 | sed -n 's/.*selected \([0-9]*\) skill.*/\1/p' | head -n 1)"
[ "$sh_count" = "$ps_count" ] || fail "second run selects ${sh_count} item(s) in bash but ${ps_count} in PowerShell"

printf '\n[parity] OK - both installers produced identical results.\n'
