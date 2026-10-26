#!/usr/bin/env bash
# Installs Diorama Kitchen: a live 3D kitchen of your Claude Code or Codex agents, in your browser.
#
#   curl -fsSL https://raw.githubusercontent.com/davidfromkansas/diorama/main/install.sh | bash
#
# Puts the kitchen in ~/.diorama-kitchen, adds a `diorama-kitchen` command to ~/.local/bin and,
# when Claude Code is installed, adds its plugin too (for /kitchen and live approvals).
set -euo pipefail

repo="${DIORAMA_KITCHEN_REPO:-https://github.com/davidfromkansas/diorama.git}"
ref="${DIORAMA_KITCHEN_REF:-main}"
home_dir="${DIORAMA_KITCHEN_HOME:-$HOME/.diorama-kitchen}"
bin_dir="${DIORAMA_KITCHEN_BIN:-$HOME/.local/bin}"
say() { printf '%s\n' "$*"; }
fail() { say "Diorama Kitchen: $*" >&2; exit 1; }

command -v git >/dev/null || fail "git is required. Install it, then run this again."
command -v node >/dev/null || fail "Node.js 18 or later is required (https://nodejs.org). Install it, then run this again."
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 18 ? 0 : 1)' || fail "Node.js 18 or later is required; you have $(node --version)."

# Only the kitchen's folder is downloaded (about 70 MB), not the whole Diorama app.
checkout="$home_dir/source"
if [ -d "$checkout/.git" ]; then
  say "Updating Diorama Kitchen…"
  git -C "$checkout" fetch --quiet --depth 1 origin "$ref"
  git -C "$checkout" checkout --quiet -B "$ref" FETCH_HEAD
else
  say "Downloading Diorama Kitchen…"
  mkdir -p "$home_dir"
  git clone --quiet --depth 1 --filter=blob:none --sparse --branch "$ref" "$repo" "$checkout"
fi
git -C "$checkout" sparse-checkout set .claude-plugin plugins/diorama-kitchen
kitchen="$checkout/plugins/diorama-kitchen/scripts/kitchen.mjs"
[ -f "$kitchen" ] || fail "the download looks incomplete ($kitchen is missing)."

mkdir -p "$bin_dir"
cat > "$bin_dir/diorama-kitchen" <<EOF
#!/usr/bin/env bash
exec node "$kitchen" "\$@"
EOF
chmod +x "$bin_dir/diorama-kitchen"

if command -v claude >/dev/null; then
  say "Adding the Claude Code plugin…"
  if claude plugin marketplace list 2>/dev/null | grep -qE '^[[:space:]]*> diorama$'; then
    claude plugin marketplace update diorama >/dev/null 2>&1 || true
  else
    claude plugin marketplace add davidfromkansas/diorama --sparse .claude-plugin plugins >/dev/null 2>&1 || say "  (Could not add the plugin; diorama-kitchen still works.)"
  fi
  claude plugin install diorama-kitchen@diorama >/dev/null 2>&1 || true
  claude plugin update diorama-kitchen@diorama >/dev/null 2>&1 || true
fi

say ""
say "Diorama Kitchen is installed."
say "  In your project folder, run:  diorama-kitchen"
say "  It opens the newest Claude Code or Codex session there (add --claude or --codex to choose)."
command -v claude >/dev/null && say "  In Claude Code you can also type /kitchen."
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) say ""; say "Add $bin_dir to your PATH to use it, for example:"
     say "  echo 'export PATH=\"$bin_dir:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
esac
