#!/usr/bin/env bash
#
# get-github-folder.sh
# -----------------------------------------------------------------------------
# Download a single folder OR file from a GitHub repository without cloning the
# whole tree. Useful when copying a skill that ships many `references/` files.
#
#   ./scripts/get-github-folder.sh <github-url> [output-dir]
#
# Folder (tree URL) → sparse git clone of that path only
# File   (blob URL) → curl from raw.githubusercontent.com
#
# Inspired by the Data Science Workbook "Downloading a single folder or file
# from GitHub" tutorial (SVN-based). GitHub removed SVN support in Jan 2024, so
# this script uses git sparse-checkout + raw HTTPS instead:
#   https://datascience.101workbook.org/07-wrangling/01-file-access/03e-download-github-folders-svn/
#
# Compatible with Bash 3.2 (default macOS shell).
# Requires: git (folders), curl (files).
# -----------------------------------------------------------------------------

set -euo pipefail

# Absolute directory containing this script (default download location).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  get-github-folder.sh <github-url> [output-dir]

Download one folder or one file from a public (or auth'd) GitHub repo without
cloning everything.

URL forms:
  Folder  https://github.com/<owner>/<repo>/tree/<ref>/<path/to/folder>
  File    https://github.com/<owner>/<repo>/blob/<ref>/<path/to/file>
  Raw     https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path/to/file>

Arguments:
  github-url    GitHub tree / blob / raw URL (copy from the browser address bar)
  output-dir    Destination parent directory. Omit (or pass "") to download
                next to this script (scripts/). Result is written as
                <output-dir>/<basename>.

Options:
  -h, --help    Show this help

Examples:
  # Folder → scripts/security-review/
  ./scripts/get-github-folder.sh \
    https://github.com/ServerJon/ai-forge/tree/main/skills/common/security-review

  # File → ./vendor/SKILL.md
  ./scripts/get-github-folder.sh \
    https://github.com/ServerJon/ai-forge/blob/main/skills/common/gh/SKILL.md \
    ./vendor

Notes:
  • Prefer the browser URL as-is — no need to rewrite tree/blob → trunk.
  • The old `svn export` flow from older tutorials no longer works on GitHub.
  • Private repos: `gh auth login` (folders) or pass credentials to curl (files).
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# --- args --------------------------------------------------------------------

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ -z "${1:-}" ]; then
  usage >&2
  exit 1
fi

URL="$1"

# Empty / omitted second arg → download beside this script.
# Non-empty → must resolve to an existing directory (or be creatable).
if [ -z "${2:-}" ]; then
  OUTPUT_DIR="$SCRIPT_DIR"
else
  OUTPUT_DIR="$2"
  if [ -e "$OUTPUT_DIR" ] && [ ! -d "$OUTPUT_DIR" ]; then
    die "output path exists but is not a directory: $OUTPUT_DIR"
  fi
  if [ ! -d "$OUTPUT_DIR" ]; then
    parent="$(dirname "$OUTPUT_DIR")"
    [ -d "$parent" ] || die "invalid output path (parent does not exist): $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR" || die "could not create output directory: $OUTPUT_DIR"
  fi
  # Resolve to absolute so the success message is unambiguous.
  OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
fi

# --- parse GitHub URL --------------------------------------------------------
# Accepts:
#   https://github.com/owner/repo/tree/ref/path/to/folder
#   https://github.com/owner/repo/blob/ref/path/to/file
#   https://raw.githubusercontent.com/owner/repo/ref/path/to/file
#   (http:// and host without scheme also ok)
#
# Note: refs with slashes (e.g. `feature/foo`) are not supported — GitHub's
# web URL form is ambiguous there. Use a branch tip commit SHA instead.

normalized="$URL"
normalized="${normalized#https://}"
normalized="${normalized#http://}"
normalized="${normalized#www.}"

mode="" # folder | file
owner=""
repo=""
ref=""
path_rest=""

case "$normalized" in
  github.com/*)
    rest="${normalized#github.com/}"
    rest="${rest%/}"

    owner="${rest%%/*}"
    rest="${rest#*/}"
    repo="${rest%%/*}"
    rest="${rest#*/}"
    kind="${rest%%/*}" # tree | blob
    rest="${rest#*/}"
    ref="${rest%%/*}"
    path_rest="${rest#*/}"

    case "$kind" in
      tree) mode="folder" ;;
      blob) mode="file" ;;
      *) die "URL must contain /tree/<ref>/... or /blob/<ref>/... (got: $URL)" ;;
    esac
    ;;
  raw.githubusercontent.com/*)
    # raw.githubusercontent.com/owner/repo/ref/path/to/file
    mode="file"
    rest="${normalized#raw.githubusercontent.com/}"
    rest="${rest%/}"

    owner="${rest%%/*}"
    rest="${rest#*/}"
    repo="${rest%%/*}"
    rest="${rest#*/}"
    ref="${rest%%/*}"
    path_rest="${rest#*/}"
    ;;
  *)
    die "not a GitHub URL: $URL"
    ;;
esac

[ -n "$owner" ] && [ -n "$repo" ] || die "could not parse owner/repo from: $URL"
[ -n "$ref" ] || die "missing branch/tag/commit in URL: $URL"
# When the URL has no path after the ref, path_rest equals ref (no slash left).
if [ "$path_rest" = "$ref" ] || [ -z "$path_rest" ]; then
  die "URL must point at a folder or file path, not the repo root: $URL"
fi

# Strip .git suffix if someone pasted a clone-style host path by mistake
repo="${repo%.git}"

item_name="$(basename "$path_rest")"
dest="$OUTPUT_DIR/$item_name"

if [ -e "$dest" ]; then
  die "destination already exists: $dest"
fi

# --- download ----------------------------------------------------------------

download_file() {
  need_cmd curl

  # Same idea as the workbook's `wget` raw-URL flow, without needing to open
  # the Raw button first — we build the raw URL from the blob URL.
  raw_url="https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${path_rest}"

  printf '→ fetching file: %s@%s:%s\n' "$owner/$repo" "$ref" "$path_rest"

  http_code="$(
    curl -sSL -w '%{http_code}' -o "$dest" "$raw_url" 2>"$tmp/curl.err" || true
  )"

  if [ "$http_code" != "200" ]; then
    rm -f "$dest"
    if [ -s "$tmp/curl.err" ]; then
      cat "$tmp/curl.err" >&2
    fi
    die "file download failed (HTTP ${http_code:-?}). Private repo? use a token: curl -H \"Authorization: Bearer \$GITHUB_TOKEN\" …"
  fi

  printf '✓ downloaded → %s\n' "$dest"
  printf '  (%s bytes)\n' "$(wc -c <"$dest" | tr -d ' ')"
}

download_folder() {
  need_cmd git

  # Partial clone + sparse-checkout fetches only the blobs under $path_rest.
  # Replaces the workbook's `svn export` + tree→trunk rewrite (SVN sunset 2024).
  repo_url="https://github.com/${owner}/${repo}.git"

  printf '→ cloning sparsely: %s@%s:%s\n' "$owner/$repo" "$ref" "$path_rest"

  # Skip template hooks (some sandboxed / restricted environments cannot write
  # into .git/hooks). --filter=blob:none avoids unrelated blobs; --sparse keeps
  # the worktree empty until we set the path.
  git_clone() {
    git -c init.templateDir= -c core.hooksPath=/dev/null \
      clone --depth 1 --filter=blob:none --sparse "$@"
  }

  if ! git_clone --branch "$ref" "$repo_url" "$tmp/repo" 2>"$tmp/clone.err"; then
    # --branch fails for raw commit SHAs; retry without it and checkout the ref.
    rm -rf "$tmp/repo"
    if ! git_clone "$repo_url" "$tmp/repo" 2>>"$tmp/clone.err"; then
      cat "$tmp/clone.err" >&2
      die "git clone failed (is the repo private? run: gh auth login)"
    fi
    git -C "$tmp/repo" fetch --depth 1 origin "$ref" 2>>"$tmp/clone.err" \
      || { cat "$tmp/clone.err" >&2; die "could not fetch ref: $ref"; }
    git -C "$tmp/repo" checkout --detach FETCH_HEAD 2>>"$tmp/clone.err" \
      || { cat "$tmp/clone.err" >&2; die "could not checkout ref: $ref"; }
  fi

  git -C "$tmp/repo" sparse-checkout set "$path_rest"

  src="$tmp/repo/$path_rest"
  [ -d "$src" ] || die "folder not found in repo: $path_rest (check the URL path)"

  # Copy without the .git metadata — just the skill files.
  cp -R "$src" "$dest"

  printf '✓ downloaded → %s\n' "$dest"
  printf '  (%s files)\n' "$(find "$dest" -type f | wc -l | tr -d ' ')"
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/gh-folder.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

case "$mode" in
  file) download_file ;;
  folder) download_folder ;;
  *) die "internal error: unknown mode '$mode'" ;;
esac
