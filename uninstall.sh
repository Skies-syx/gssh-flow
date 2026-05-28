#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${GSSH_HOME:-"$HOME/.config/gssh-flow"}"
WORKFLOW_FILE="$INSTALL_DIR/workflow.zsh"
SOURCE_LINE='[[ -f "$HOME/.config/gssh-flow/workflow.zsh" ]] && source "$HOME/.config/gssh-flow/workflow.zsh"'

info() {
  printf '[gssh-flow] %s\n' "$*"
}

remove_source_line() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v source_line="$SOURCE_LINE" '
    $0 == "# Added by gssh-flow" {
      marker = 1
      next
    }
    marker && $0 == source_line {
      marker = 0
      next
    }
    marker {
      print "# Added by gssh-flow"
      marker = 0
    }
    $0 != source_line {
      print
    }
    END {
      if (marker) print "# Added by gssh-flow"
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  info "updated $file"
}

main() {
  remove_source_line "$HOME/.zshrc"
  remove_source_line "$HOME/.zprofile"

  if [[ -f "$WORKFLOW_FILE" ]]; then
    rm -f "$WORKFLOW_FILE"
    info "removed $WORKFLOW_FILE"
  fi

  info "kept $INSTALL_DIR/hosts.jsonl if it exists"
  info "remove $INSTALL_DIR manually if you want to delete saved credentials"
}

main "$@"
