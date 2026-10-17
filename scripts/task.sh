#!/usr/bin/env bash
# Cross-platform task runner for Antares.
#
# `make` is not installed everywhere (notably a stock Windows dev box), so this
# script performs the same jobs using only bash + go + bun. The Makefile remains
# the canonical interface where GNU make exists; keep the two in step.
#
# Usage:
#   ./scripts/task.sh build          # single binary with the dashboard embedded
#   ./scripts/task.sh build-web      # dashboard only, into internal/server/dist
#   ./scripts/task.sh build-api      # backend only, no dashboard
#   ./scripts/task.sh test|vet|check|fmt
#   ./scripts/task.sh typecheck|web-test
#   ./scripts/task.sh release        # cross-compile every platform into dist/release
#   ./scripts/task.sh clean|doctor|help
#
# Windows: run this from Git Bash, not from WSL. A stock install puts WSL's
# C:\Windows\System32\bash.exe ahead of Git's on PATH, and WSL has no Go, Bun or
# Windows .exe execution, so the script would fail with "cannot execute binary
# file: Exec format error". Invoke it explicitly if unsure:
#   "C:/Program Files/Git/bin/bash.exe" -lc './scripts/task.sh build'
#
# Env knobs mirror the Makefile: GO, BUN, VERSION, COMMIT, DATE, PREFIX, OUT.

set -euo pipefail

cd "$(dirname "$0")/.."

GO="${GO:-go}"
BUN="${BUN:-bun}"
# $HOME can arrive empty in stripped-down shells, and in that case `~` expands
# from passwd, which this Git-for-Windows bash reports as a /home/<user> path
# that may not exist. Check the real candidates in order instead.
detect_home() {
  local h
  # Environment variables are unreliable across contexts: $HOME can be empty
  # (leaving `~` to expand to a passwd-derived /home/<user>) and $USERPROFILE
  # can be absent from a script's environment even when the shell has it. Ask
  # the filesystem instead: the profile is whichever candidate actually holds
  # the tool directories we need.
  # A generic dotfile directory is not proof of the right profile: a passwd-only
  # home such as /home/<user> can carry a .config while the tool installations
  # live under the real Windows profile. Prefer a home that holds the tool.
  for h in "${HOME:-}" "${USERPROFILE:-}"; do
    if [ -n "$h" ] && { [ -d "$h/.bun" ] || [ -d "$h/.local/sdk" ] || [ -d "$h/go" ]; }; then
      printf '%s' "$h"; return 0
    fi
  done
  # Git for Windows reports a profile under /c/Users when $HOME is unset.
  for h in /c/Users/*/; do
    h="${h%/}"
    if [ -d "$h/.bun" ]; then printf '%s' "$h"; return 0; fi
  done
  for h in "$(cd ~ 2>/dev/null && pwd || true)" "$(pwd)"; do
    if [ -n "$h" ] && [ -d "$h" ]; then printf '%s' "$h"; return 0; fi
  done
  pwd
}
HOME_DIR="$(detect_home)"
PREFIX="${PREFIX:-$HOME_DIR/.local}"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# `command -v bun` can resolve to a launcher that is not runnable here: a
# WSL-style /mnt/c/... shim, or a wrapper for another platform. Probe the
# candidate for real and fall back to the conventional install paths.
resolve_tool() {
  local name="$1"; shift
  local candidate
  candidate="$(command -v "$name" 2>/dev/null || true)"
  if [ -n "$candidate" ] && "$candidate" --version >/dev/null 2>&1; then
    printf '%s' "$candidate"; return 0
  fi
  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    if [ -x "$candidate" ] && "$candidate" --version >/dev/null 2>&1; then
      printf '%s' "$candidate"; return 0
    fi
  done
  return 1
}

# Only re-resolve when the caller did not pass an explicit override. The test is
# on whether the value is non-empty and runnable, which also covers a stale or
# cross-platform shim inherited from the environment.
if ! "$GO" version >/dev/null 2>&1; then
  GO="$(resolve_tool go "$HOME_DIR/.local/sdk/go/bin/go" "$HOME_DIR/go/bin/go" 2>/dev/null || printf '%s' go)"
fi
if ! "$BUN" --version >/dev/null 2>&1; then
  BUN="$(resolve_tool bun "$HOME_DIR/.bun/bin/bun.exe" "$HOME_DIR/.bun/bin/bun" 2>/dev/null || printf '%s' bun)"
fi

VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo 0.1.0-dev)}"
COMMIT="${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo dev)}"
DATE="${DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

MODULE="github.com/pandamoon21/antares"
LDFLAGS="-s -w \
  -X ${MODULE}/internal/version.Version=${VERSION} \
  -X ${MODULE}/internal/version.Commit=${COMMIT} \
  -X ${MODULE}/internal/version.Date=${DATE}"

# `//go:embed all:dist` needs at least one file in the directory.
ensure_embed_placeholder() {
  mkdir -p internal/server/dist
  [ -f internal/server/dist/.gitkeep ] || touch internal/server/dist/.gitkeep
}

build_web() {
  have "$BUN" || die "bun not found; install it or set BUN=/path/to/bun (needed for the dashboard)."
  info "building the dashboard"
  ( cd web && "$BUN" run build )
  rm -rf internal/server/dist
  cp -r web/dist internal/server/dist
  ensure_embed_placeholder
}

build() {
  build_web
  info "building bin/antares ($VERSION)"
  mkdir -p bin
  "$GO" build -trimpath -ldflags "$LDFLAGS" -o bin/antares ./cmd/antares
  info "built bin/antares ($VERSION)"
}

build_api() {
  info "building bin/antares without the dashboard"
  mkdir -p bin
  "$GO" build -trimpath -ldflags "$LDFLAGS" -o bin/antares ./cmd/antares
}

cmd="${1:-help}"
case "$cmd" in
  build)      build ;;
  build-web)  build_web ;;
  build-api)  ensure_embed_placeholder; build_api ;;
  install-cli)
    build
    mkdir -p "$PREFIX/bin"
    cp -f bin/antares "$PREFIX/bin/antares"
    info "installed $PREFIX/bin/antares" ;;
  test)       "$GO" test ./... ;;
  vet)        "$GO" vet ./... ;;
  fmt)        "$GO" fmt ./... ;;
  typecheck)  ( cd web && "$BUN" x tsc -b --noEmit ) ;;
  web-test)   ( cd web && "$BUN" test ) ;;
  check)
    "$GO" vet ./...
    "$GO" test ./...
    ( cd web && "$BUN" x tsc -b --noEmit )
    ( cd web && "$BUN" test ) ;;
  release)
    GO="$GO" BUN="$BUN" VERSION="$VERSION" ./scripts/release-build.sh ;;
  clean)
    rm -rf bin dist internal/server/dist
    ensure_embed_placeholder
    info "cleaned" ;;
  doctor)     "$GO" run ./cmd/antares doctor ;;
  help|*)
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
