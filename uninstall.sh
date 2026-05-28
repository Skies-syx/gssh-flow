#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${GSSH_HOME:-"$HOME/.config/gssh-flow"}"
WORKFLOW_FILE="$INSTALL_DIR/workflow.zsh"
DEFAULT_SOURCE_LINE='[[ -f "$HOME/.config/gssh-flow/workflow.zsh" ]] && source "$HOME/.config/gssh-flow/workflow.zsh"'
SOURCE_LINE=""

info() {
  printf '[gssh-flow] %s\n' "$*"
}

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

source_line_for() {
  local workflow_file="$1"
  local default_workflow_file="$HOME/.config/gssh-flow/workflow.zsh"
  if [[ "$workflow_file" == "$default_workflow_file" ]]; then
    printf '%s\n' "$DEFAULT_SOURCE_LINE"
  else
    printf '[[ -f %s ]] && source %s\n' "$(shell_quote "$workflow_file")" "$(shell_quote "$workflow_file")"
  fi
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
    marker && ($0 == source_line || $0 == default_source_line) {
      marker = 0
      next
    }
    marker {
      print "# Added by gssh-flow"
      marker = 0
    }
    $0 != source_line && $0 != default_source_line {
      print
    }
    END {
      if (marker) print "# Added by gssh-flow"
    }
  ' source_line="$SOURCE_LINE" default_source_line="$DEFAULT_SOURCE_LINE" "$file" > "$tmp"
  mv "$tmp" "$file"
  info "updated $file"
}

main() {
  SOURCE_LINE="$(source_line_for "$WORKFLOW_FILE")"

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
