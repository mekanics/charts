#!/bin/bash
###
### repo.sh — lazy clone/pull wrapper for git repos
###
### Usage:
###   repo.sh <project-slug> [action]
###
### Actions:
###   auto    Clone if missing, pull if exists (default)
###   clone   Force a fresh clone, removing any existing copy
###   path    Return the local path only — no clone, no pull
###
### Options:
###   -h, --help    Show this help message and exit
###
### Environment:
###   REPOS_DIR    Directory where repos are cloned (default: /home/node/projects)
###   MANIFEST     Path to repos.yaml manifest (default: /home/node/.openclaw/workspace/projects/repos.yaml)
###
### Repos are defined in MANIFEST as a YAML map keyed by project slug.
### Cloned into REPOS_DIR (emptyDir — ephemeral, wiped on pod restart).
### GitHub is the source of truth.

set -euo pipefail

help() {
    awk -F'### ' '/^###/ { print $2 }' "$0"
    exit
}

REPOS_DIR="${REPOS_DIR:-/home/node/projects}"
MANIFEST="${MANIFEST:-/home/node/.openclaw/workspace/projects/repos.yaml}"

action_path() {
    echo "$REPO_PATH"
}

action_clone() {
    rm -rf "$REPO_PATH"
    echo "Cloning $SLUG ($BRANCH)..." >&2
    git clone --branch "$BRANCH" "$URL" "$REPO_PATH" >&2
    echo "$REPO_PATH"
}

action_auto() {
    if [ -d "$REPO_PATH/.git" ]; then
        git -C "$REPO_PATH" pull --ff-only >&2 || echo "Warning: pull failed for $SLUG, using cached copy" >&2
        echo "$REPO_PATH"
    else
        mkdir -p "$REPOS_DIR"
        echo "Cloning $SLUG ($BRANCH)..." >&2
        git clone --branch "$BRANCH" "$URL" "$REPO_PATH" >&2
        echo "$REPO_PATH"
    fi
}

resolve_slug() {
    local slug="$1"

    # Restrict slugs to safe characters — prevents regex injection in grep and
    # path traversal via REPO_PATH construction.
    if ! printf '%s' "$slug" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        echo "Error: invalid project slug '$slug' — only alphanumeric, hyphens, and underscores allowed" >&2
        exit 1
    fi

    if [ ! -f "$MANIFEST" ]; then
        echo "Error: manifest not found: $MANIFEST" >&2
        exit 1
    fi

    # Anchored match with -A5 for url/branch keys; slug is regex-safe after validation above.
    URL=$(grep -A5 "^  ${slug}:" "$MANIFEST" | grep "url:" | head -1 | awk '{print $2}')
    BRANCH=$(grep -A5 "^  ${slug}:" "$MANIFEST" | grep "branch:" | head -1 | awk '{print $2}')
    BRANCH="${BRANCH:-main}"

    if [ -z "$URL" ]; then
        echo "Error: unknown project '$slug'" >&2
        echo "Add it to $MANIFEST first." >&2
        exit 1
    fi

    REPO_PATH="$REPOS_DIR/$slug"
}

case "${1:-}" in
    -h|--help|"")
        help
        ;;
    -*)
        echo "Error: unknown option '$1'"
        help
        ;;
    *)
        SLUG="$1"
        ACTION="${2:-auto}"
        resolve_slug "$SLUG"

        case "$ACTION" in
            path)  action_path ;;
            clone) action_clone ;;
            auto)  action_auto ;;
            *)
                echo "Error: unknown action '$ACTION'" >&2
                help
                ;;
        esac
        ;;
esac
