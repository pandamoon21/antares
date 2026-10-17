#!/usr/bin/env bash
# Antares installer for Linux and macOS.
#
# Downloads the prebuilt `antares` binary for your platform from the project's
# GitHub Releases and installs it. No build tools required.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/pandamoon21/antares/main/scripts/install.sh | bash
#
# Env knobs:
#   PREFIX=/usr/local     install dir root (binary lands in $PREFIX/bin); default ~/.local
#   ANTARES_VERSION=v0.1.0  install a specific release; default: latest
#   ANTARES_REPO=owner/name GitHub repo; default pandamoon21/antares
#
# This is the maintained fork of the deleted enowdev/antares project. See
# FORK.md for provenance. The gh CLI is optional: when present it is used
# (useful for private mirrors or to dodge API rate limits), otherwise curl
# talks to the public GitHub API and release URLs.

set -euo pipefail

REPO="${ANTARES_REPO:-pandamoon21/antares}"
VERSION="${ANTARES_VERSION:-latest}"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- detect platform --------------------------------------------------------
os="$(uname -s)"; arch="$(uname -m)"
case "$os" in
  Linux)  goos="linux" ;;
  Darwin) goos="darwin" ;;
  *) die "unsupported OS '$os' — on Windows use scripts/install.ps1" ;;
esac
case "$arch" in
  x86_64|amd64)  goarch="amd64" ;;
  arm64|aarch64) goarch="arm64" ;;
  *) die "unsupported architecture '$arch'" ;;
esac
info "platform: $goos/$goarch"

# The asset name matches scripts/release-build.sh output.
asset_for() { echo "antares_${1}_${goos}_${goarch}"; }

mkdir -p "$BINDIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
dest="$tmp/antares"

# ---- fetch ------------------------------------------------------------------
# Prefer the gh CLI (works for a private repo); otherwise use public release URLs.
if have gh; then
  info "downloading via GitHub CLI ($REPO, $VERSION)"
  ver="$VERSION"
  if [ "$ver" = "latest" ]; then
    ver="$(gh release view --repo "$REPO" --json tagName -q .tagName)" \
      || die "could not read the latest release. Is 'gh' authenticated? Try: gh auth login"
  fi
  asset="$(asset_for "$ver")"
  gh release download "$ver" --repo "$REPO" --pattern "$asset" --output "$dest" --clobber \
    || die "no asset '$asset' in release $ver. Available assets: $(gh release view "$ver" --repo "$REPO" --json assets -q '.assets[].name' | tr '\n' ' ')"
else
  have curl || die "need curl (or the gh CLI) to download."
  ver="$VERSION"
  if [ "$ver" = "latest" ]; then
    # Release assets are named antares_<version>_..., so the version has to be
    # known before the URL can be built. Ask the GitHub API for the latest tag;
    # the /releases/latest/download redirect only works for constant filenames.
    api="https://api.github.com/repos/$REPO/releases/latest"
    ver="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "$api" 2>/dev/null \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    [ -n "$ver" ] || die "could not resolve the latest release for $REPO (no releases yet?). Pass one explicitly: ANTARES_VERSION=v0.3.0"
  fi
  asset="$(asset_for "$ver")"
  url="https://github.com/$REPO/releases/download/$ver/$asset"
  info "downloading $url"
  curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "$url" -o "$dest" \
    || die "download failed for $asset. Check the release exists and carries that asset, or pass ANTARES_VERSION explicitly."
fi

[ -s "$dest" ] || die "downloaded file is empty."

# ---- install ----------------------------------------------------------------
chmod +x "$dest"
mv -f "$dest" "$BINDIR/antares"
# macOS Gatekeeper quarantines downloaded binaries; clear it so it runs.
if [ "$goos" = "darwin" ] && have xattr; then
  xattr -d com.apple.quarantine "$BINDIR/antares" 2>/dev/null || true
fi
info "installed $BINDIR/antares"
"$BINDIR/antares" --version 2>/dev/null || true

# ---- PATH --------------------------------------------------------------------
# Add $BINDIR to PATH automatically (matching the Windows installer). We append
# an export to the shell rc files that exist, guarded by a marker so re-running
# never duplicates it. Set ANTARES_NO_MODIFY_PATH=1 to skip and just be told.
add_path_line() {
  local rc="$1" marker="# added by antares installer"
  [ -e "$rc" ] || return 0
  grep -qF "$marker" "$rc" 2>/dev/null && return 0
  {
    printf '\n%s\n' "$marker"
    printf 'export PATH="%s:$PATH"\n' "$BINDIR"
  } >> "$rc"
  info "added $BINDIR to PATH in $rc"
}

case ":$PATH:" in
  *":$BINDIR:"*)
    info "run 'antares' from anywhere (open a new shell if not found yet)"
    ;;
  *)
    if [ "${ANTARES_NO_MODIFY_PATH:-0}" = "1" ]; then
      warn "$BINDIR is not on your PATH. Add it:"
      echo "    echo 'export PATH=\"$BINDIR:\$PATH\"' >> ~/.bashrc   # or ~/.zshrc"
    else
      touched=0
      # bash and zsh: both .profile-style and shell-specific rc files.
      for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        [ -e "$rc" ] && { add_path_line "$rc"; touched=1; }
      done
      # zsh with no .zshrc yet (common on macOS): create one so it takes effect.
      if [ -n "${ZSH_VERSION:-}" ] || [ "${SHELL##*/}" = "zsh" ]; then
        [ -e "$HOME/.zshrc" ] || { add_path_line "$HOME/.zshrc"; touched=1; }
      fi
      # fish keeps PATH differently.
      if [ -d "$HOME/.config/fish" ]; then
        fish_cfg="$HOME/.config/fish/config.fish"
        if ! grep -qF "# added by antares installer" "$fish_cfg" 2>/dev/null; then
          { printf '\n# added by antares installer\n'; printf 'set -gx PATH %s $PATH\n' "$BINDIR"; } >> "$fish_cfg"
          info "added $BINDIR to PATH in $fish_cfg"
          touched=1
        fi
      fi
      if [ "$touched" = "1" ]; then
        warn "PATH updated — open a NEW terminal (or 'source' your shell rc) for 'antares' to be found."
      else
        warn "$BINDIR is not on your PATH and no shell rc file was found. Add it:"
        echo "    echo 'export PATH=\"$BINDIR:\$PATH\"' >> ~/.bashrc   # or ~/.zshrc"
      fi
    fi
    ;;
esac

echo
info "next: run 'antares setup' to configure a provider, then 'antares' to start it in the background (or 'antares tui' for the terminal UI)"
