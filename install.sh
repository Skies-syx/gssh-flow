#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="gssh-flow"
INSTALL_DIR="${GSSH_HOME:-"$HOME/.config/gssh-flow"}"
WORKFLOW_FILE="$INSTALL_DIR/workflow.zsh"
HOSTS_FILE="${GSSH_HOSTS_FILE:-"$INSTALL_DIR/hosts.jsonl"}"
RAW_BASE="${GSSH_FLOW_RAW_BASE:-"https://raw.githubusercontent.com/Skies-syx/gssh-flow/main"}"
SOURCE_LINE='[[ -f "$HOME/.config/gssh-flow/workflow.zsh" ]] && source "$HOME/.config/gssh-flow/workflow.zsh"'

info() {
  printf '[gssh-flow] %s\n' "$*"
}

warn() {
  printf '[gssh-flow] warning: %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

append_source_line() {
  local file="$1"
  touch "$file"
  if ! grep -Fq "$SOURCE_LINE" "$file"; then
    {
      printf '\n# Added by gssh-flow\n'
      printf '%s\n' "$SOURCE_LINE"
    } >> "$file"
    info "updated $file"
  else
    info "$file already configured"
  fi
}

copy_or_download_workflow() {
  local script_dir source_workflow
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P || true)"
  source_workflow="${GSSH_FLOW_SOURCE_WORKFLOW:-}"

  if [[ -z "$source_workflow" && -n "$script_dir" && -f "$script_dir/src/workflow.zsh" ]]; then
    source_workflow="$script_dir/src/workflow.zsh"
  fi

  if [[ -n "$source_workflow" && -f "$source_workflow" ]]; then
    cp "$source_workflow" "$WORKFLOW_FILE"
    return
  fi

  if need_cmd curl; then
    curl -fsSL "$RAW_BASE/src/workflow.zsh" -o "$WORKFLOW_FILE"
  elif need_cmd wget; then
    wget -qO "$WORKFLOW_FILE" "$RAW_BASE/src/workflow.zsh"
  else
    warn "curl or wget is required to download workflow.zsh"
    exit 1
  fi
}

main() {
  info "installing to $INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  chmod 700 "$INSTALL_DIR" 2>/dev/null || true

  copy_or_download_workflow
  chmod 644 "$WORKFLOW_FILE" 2>/dev/null || true

  if [[ ! -f "$HOSTS_FILE" ]]; then
    : > "$HOSTS_FILE"
    info "created $HOSTS_FILE"
  else
    info "kept existing $HOSTS_FILE"
  fi
  chmod 600 "$HOSTS_FILE" 2>/dev/null || true

  append_source_line "$HOME/.zshrc"
  append_source_line "$HOME/.zprofile"

  local missing=0
  need_cmd fzf || { warn "missing fzf. Install on macOS: brew install fzf"; missing=1; }
  need_cmd sshpass || { warn "missing sshpass. Install on macOS: brew install hudochenkov/sshpass/sshpass"; missing=1; }
  need_cmd python3 || { warn "missing python3"; missing=1; }

  info "done"
  info "next: run 'source ~/.zshrc' or restart your terminal"
  if [[ "$missing" -ne 0 ]]; then
    warn "some dependencies are missing; install them before using gssh-flow"
  fi
}

main "$@"
