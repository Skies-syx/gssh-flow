# gssh-flow: fzf-powered SSH workflow for Ghostty and terminal-first users.
# Safe-mode only: uses ~/.ssh/known_hosts and sshpass -e password entry.

GSSH_FLOW_LOADED=1

export GSSH_HOME="${GSSH_HOME:-$HOME/.config/gssh-flow}"
export GSSH_HOSTS_FILE="${GSSH_HOSTS_FILE:-$GSSH_HOME/hosts.jsonl}"
export GSSH_LEGACY_HOSTS_FILE="${GSSH_LEGACY_HOSTS_FILE:-$HOME/.ssh/hosts.txt}"
export GSSH_AUTO_MIGRATE_LEGACY="${GSSH_AUTO_MIGRATE_LEGACY:-0}"
export GSSH_CLEAR_BEFORE_CONNECT="${GSSH_CLEAR_BEFORE_CONNECT:-0}"

typeset -g _GSSH_FZF_BIN=""
typeset -g _GSSH_SSHPASS_BIN=""
typeset -g _GSSH_PYTHON_BIN=""
typeset -g _GSSH_LEGACY_MIGRATED=0

function _gssh_bin() {
    local name="$1"
    local fallback="$2"
    local bin
    bin=$(command -v "$name" 2>/dev/null) && { echo "$bin"; return 0; }
    [[ -n "$fallback" && -x "$fallback" ]] && echo "$fallback"
}

function _gssh_fzf() {
    if [[ -n "$_GSSH_FZF_BIN" && -x "$_GSSH_FZF_BIN" ]]; then
        print -r -- "$_GSSH_FZF_BIN"
        return 0
    fi
    _GSSH_FZF_BIN="$(_gssh_bin fzf /opt/homebrew/bin/fzf)"
    print -r -- "$_GSSH_FZF_BIN"
}

function _gssh_sshpass() {
    if [[ -n "$_GSSH_SSHPASS_BIN" && -x "$_GSSH_SSHPASS_BIN" ]]; then
        print -r -- "$_GSSH_SSHPASS_BIN"
        return 0
    fi
    _GSSH_SSHPASS_BIN="$(_gssh_bin sshpass /opt/homebrew/bin/sshpass)"
    print -r -- "$_GSSH_SSHPASS_BIN"
}

function _gssh_python() {
    if [[ -n "$_GSSH_PYTHON_BIN" && -x "$_GSSH_PYTHON_BIN" ]]; then
        print -r -- "$_GSSH_PYTHON_BIN"
        return 0
    fi
    _GSSH_PYTHON_BIN="$(_gssh_bin python3 /usr/bin/python3)"
    print -r -- "$_GSSH_PYTHON_BIN"
}

function _gssh_require() {
    local missing=0
    local fzf_bin sshpass_bin python_bin
    fzf_bin="$(_gssh_fzf)"
    sshpass_bin="$(_gssh_sshpass)"
    python_bin="$(_gssh_python)"

    [[ -z "$fzf_bin" ]] && { echo "缺少 fzf：brew install fzf" >&2; missing=1; }
    [[ -z "$sshpass_bin" ]] && { echo "缺少 sshpass：brew install hudochenkov/sshpass/sshpass" >&2; missing=1; }
    [[ -z "$python_bin" ]] && { echo "缺少 python3" >&2; missing=1; }
    command -v ssh >/dev/null 2>&1 || { echo "缺少 ssh" >&2; missing=1; }
    command -v scp >/dev/null 2>&1 || { echo "缺少 scp" >&2; missing=1; }
    command -v ssh-keygen >/dev/null 2>&1 || { echo "缺少 ssh-keygen" >&2; missing=1; }
    return "$missing"
}

function _gssh_prepare() {
    mkdir -p "$GSSH_HOME" "${GSSH_HOSTS_FILE:h}"
    [[ -f "$GSSH_HOSTS_FILE" ]] || : > "$GSSH_HOSTS_FILE"
    chmod 700 "$GSSH_HOME" 2>/dev/null
    chmod 600 "$GSSH_HOSTS_FILE" 2>/dev/null
}

function _gssh_clean_path() {
    local p="$1"
    p="${p//$'\r'/}"
    p="${p//$'\n'/}"
    while [[ "$p" == [[:space:]]* ]]; do
        p="${p#[[:space:]]}"
    done
    while [[ "$p" == *[[:space:]] ]]; do
        p="${p%[[:space:]]}"
    done
    p="${p% }"
    p="${p#\'}"
    p="${p%\'}"
    p="${p#\"}"
    p="${p%\"}"
    p="${(Q)p}"
    print -r -- "$p"
}

function _gssh_clean_local_path() {
    local p
    p="$(_gssh_clean_path "$1")"
    if [[ "$p" == "~" ]]; then
        p="$HOME"
    elif [[ "$p" == "~/"* ]]; then
        p="$HOME/${p#\~/}"
    fi
    print -r -- "$p"
}

function _gssh_read_path() {
    local prompt="$1"
    local value=""
    local line=""
    print -n "$prompt" >&2
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "$line" == *\\ ]]; then
            value+="${line%\\}"
            print -n "> " >&2
            continue
        fi
        value+="$line"
        break
    done
    print -r -- "$value"
}

function _gssh_set_title() {
    local title="$1"
    printf '\033]0;%s\007\033]2;%s\007' "$title" "$title"
}

function _gssh_basename() {
    local p="${1%/}"
    print -r -- "${p:t}"
}

function _gssh_local_size_kb() {
    local target_path="$1"
    [[ -e "$target_path" ]] || { echo 0; return 0; }
    du -sk "$target_path" 2>/dev/null | awk '{print int($1)}'
}

function _gssh_human_kb() {
    local kb="${1:-0}"
    if (( kb >= 1048576 )); then
        printf '%d.%02dG' $(( kb / 1048576 )) $(( (kb % 1048576) * 100 / 1048576 ))
    elif (( kb >= 1024 )); then
        printf '%d.%02dM' $(( kb / 1024 )) $(( (kb % 1024) * 100 / 1024 ))
    else
        printf '%dK' "$kb"
    fi
}

function _gssh_progress_line() {
    local done_kb="${1:-0}"
    local total_kb="${2:-0}"
    local percent=0
    (( done_kb < 0 )) && done_kb=0
    if (( total_kb > 0 )); then
        percent=$(( done_kb * 100 / total_kb ))
        (( percent > 100 )) && percent=100
        printf '\rProgress: %3d%%  %s / %s' "$percent" "$(_gssh_human_kb "$done_kb")" "$(_gssh_human_kb "$total_kb")" >&2
    else
        printf '\rProgress: %s' "$(_gssh_human_kb "$done_kb")" >&2
    fi
}

function _gssh_remote_size_kb() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local remote_path="$5"
    local sshpass_bin remote_q

    sshpass_bin="$(_gssh_sshpass)"
    [[ -z "$sshpass_bin" ]] && { echo 0; return 0; }
    remote_q="${(q)remote_path}"
    SSHPASS="$password" "$sshpass_bin" -e ssh -p "$port" \
        -o StrictHostKeyChecking=accept-new \
        -o NumberOfPasswordPrompts=1 \
        -o LogLevel=ERROR \
        "$user@$ip" "du -sk $remote_q 2>/dev/null | awk '{print int(\$1)}'" 2>/dev/null
}

function _gssh_remote_is_dir() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local remote_path="$5"
    local sshpass_bin remote_q

    sshpass_bin="$(_gssh_sshpass)"
    [[ -z "$sshpass_bin" ]] && return 1
    remote_q="${(q)remote_path}"
    SSHPASS="$password" "$sshpass_bin" -e ssh -p "$port" \
        -o StrictHostKeyChecking=accept-new \
        -o NumberOfPasswordPrompts=1 \
        -o LogLevel=ERROR \
        "$user@$ip" "test -d $remote_q" >/dev/null 2>&1
}

function _gssh_download_target_path() {
    local remote_path="$1"
    local local_path="$2"
    local base
    if [[ -d "$local_path" ]]; then
        base="$(_gssh_basename "$remote_path")"
        print -r -- "${local_path%/}/$base"
    else
        print -r -- "$local_path"
    fi
}

function _gssh_upload_target_path() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local local_path="$5"
    local remote_path="$6"
    local base
    if _gssh_remote_is_dir "$ip" "$port" "$user" "$password" "$remote_path"; then
        base="$(_gssh_basename "$local_path")"
        print -r -- "${remote_path%/}/$base"
    else
        print -r -- "$remote_path"
    fi
}

function _gssh_json() {
    local action="$1"
    shift
    local python_bin
    python_bin="$(_gssh_python)"
    [[ -z "$python_bin" ]] && { echo "缺少 python3" >&2; return 1; }

    GSSH_HOSTS_FILE="$GSSH_HOSTS_FILE" "$python_bin" - "$action" "$@" <<'PY'
import json
import os
import shutil
import sys
from pathlib import Path

path = Path(os.environ["GSSH_HOSTS_FILE"]).expanduser()
action = sys.argv[1]
args = sys.argv[2:]

def read_hosts():
    hosts = []
    if not path.exists():
        return hosts
    with path.open("r", encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{path}:{n}: JSON 解析失败: {exc}")
            ip = str(item.get("ip", "")).strip()
            user = str(item.get("user", "")).strip()
            password = str(item.get("password", ""))
            port = int(item.get("port", 22) or 22)
            if not ip or not user:
                continue
            hosts.append({"ip": ip, "user": user, "password": password, "port": port})
    return hosts

def write_hosts(hosts):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))
    tmp = path.with_suffix(path.suffix + ".tmp")
    seen = {}
    order = []
    for h in hosts:
        ip = h["ip"]
        if ip not in seen:
            order.append(ip)
        seen[ip] = h
    with tmp.open("w", encoding="utf-8") as fh:
        for ip in order:
            fh.write(json.dumps(seen[ip], ensure_ascii=False, separators=(",", ":")) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(path)
    os.chmod(path, 0o600)

hosts = read_hosts()

if action == "list_ips":
    query = args[0] if args else ""
    for h in hosts:
        if not query or query in h["ip"]:
            print(h["ip"])
elif action == "get":
    ip = args[0]
    for h in hosts:
        if h["ip"] == ip:
            print(json.dumps(h, ensure_ascii=False, separators=(",", ":")))
            break
    else:
        raise SystemExit(2)
elif action == "auths":
    auths = sorted({f'{h["user"]} | {h["password"]}' for h in hosts})
    for auth in auths:
        print(auth)
elif action == "machine_creds":
    for h in hosts:
        print(f'{h["ip"]}\t{h["user"]}\t{h["port"]}\t{h["password"]}')
elif action == "upsert":
    ip, user, password, port = args[0], args[1], args[2], int(args[3] or 22)
    hosts = [h for h in hosts if h["ip"] != ip]
    hosts.append({"ip": ip, "user": user, "password": password, "port": port})
    write_hosts(hosts)
elif action == "migrate":
    legacy = Path(args[0]).expanduser()
    if not legacy.exists():
        write_hosts(hosts)
        raise SystemExit(0)
    migrated = {h["ip"]: h for h in hosts}
    current = None
    with legacy.open("r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "|" in line:
                parts = line.split("|")
                if len(parts) >= 3:
                    user = parts[0]
                    port = parts[-1]
                    password = "|".join(parts[1:-1])
                    current = {"user": user, "password": password, "port": int(port or 22)}
                continue
            if current:
                if line not in migrated:
                    migrated[line] = {
                        "ip": line,
                        "user": current["user"],
                        "password": current["password"],
                        "port": current["port"],
                    }
    write_hosts(list(migrated.values()))
elif action == "count":
    print(len(hosts))
else:
    raise SystemExit(f"unknown action: {action}")
PY
}

function _gssh_migrate_once() {
    _gssh_prepare
    [[ "$GSSH_AUTO_MIGRATE_LEGACY" == "1" ]] || return 0
    [[ "$_GSSH_LEGACY_MIGRATED" == "1" ]] && return 0
    [[ -f "$GSSH_LEGACY_HOSTS_FILE" ]] || { _GSSH_LEGACY_MIGRATED=1; return 0; }
    _gssh_json migrate "$GSSH_LEGACY_HOSTS_FILE"
    _GSSH_LEGACY_MIGRATED=1
}

function gssh-migrate-legacy() {
    local old_auto="$GSSH_AUTO_MIGRATE_LEGACY"
    GSSH_AUTO_MIGRATE_LEGACY=1
    _GSSH_LEGACY_MIGRATED=0
    _gssh_migrate_once
    local rc=$?
    GSSH_AUTO_MIGRATE_LEGACY="$old_auto"
    return "$rc"
}

function _gssh_select_ip() {
    local query="$1"
    local fzf_bin ips
    fzf_bin="$(_gssh_fzf)"
    [[ -z "$fzf_bin" ]] && { echo "缺少 fzf：brew install fzf" >&2; return 1; }
    _gssh_migrate_once
    ips="$(_gssh_json list_ips "$query")" || return 1
    [[ -z "$ips" ]] && { echo "暂无匹配主机。可先运行 nssh 录入。" >&2; return 1; }
    printf '%s\n' "$ips" | "$fzf_bin" --query="$query" --prompt="搜索主机 > " --layout=reverse --height=40% --border
}

function _gssh_host_json() {
    local ip="$1"
    _gssh_json get "$ip"
}

function _gssh_host_field() {
    local host_json="$1"
    local field="$2"
    local python_bin
    python_bin="$(_gssh_python)"
    HOST_JSON="$host_json" HOST_FIELD="$field" "$python_bin" <<'PY'
import json
import os

item = json.loads(os.environ["HOST_JSON"])
print(item.get(os.environ["HOST_FIELD"], ""))
PY
}

function _gssh_host_fields() {
    local host_json="$1"
    local python_bin
    python_bin="$(_gssh_python)"
    [[ -z "$python_bin" ]] && { echo "缺少 python3" >&2; return 1; }
    HOST_JSON="$host_json" "$python_bin" <<'PY'
import json
import os

item = json.loads(os.environ["HOST_JSON"])
print(str(item.get("ip", "")))
print(str(item.get("user", "")))
print(str(item.get("password", "")))
print(str(item.get("port", 22) or 22))
PY
}

function _gssh_load_host_fields() {
    local host_json="$1"
    local -a fields
    fields=("${(@f)$(_gssh_host_fields "$host_json")}") || return 1
    if (( ${#fields} < 4 )); then
        echo "主机记录解析失败。" >&2
        return 1
    fi
    ip="${fields[1]}"
    user="${fields[2]}"
    password="${fields[3]}"
    port="${fields[4]}"
}

function _gssh_forget_host_key() {
    local ip="$1"
    local port="${2:-22}"
    echo "检测到 host key 变化："
    echo "host: $ip"
    echo "port: $port"
    print -n "确认这是机器重装/快照回滚/IP 复用，并删除旧 known_hosts 记录？输入 yes 确认: "
    local ans
    read ans
    [[ "$ans" != "yes" ]] && { echo "已取消，未删除 known_hosts。"; return 1; }
    ssh-keygen -R "$ip" >/dev/null 2>&1
    ssh-keygen -R "[$ip]:$port" >/dev/null 2>&1
    echo "旧 host key 已删除，正在重试..."
}

function _gssh_remote_title_command() {
    local title="$1"
    local python_bin
    python_bin="$(_gssh_python)"
    GSSH_TITLE="$title" "$python_bin" <<'PY'
import os
import shlex

title = os.environ["GSSH_TITLE"].replace("\033", "").replace("\007", "")
title_q = shlex.quote(title)
rc = f"""export TERM=xterm-256color
export COLORTERM=truecolor
[[ -f ~/.bashrc ]] && source ~/.bashrc
export TERM=xterm-256color
export COLORTERM=truecolor
__gssh_set_title() {{ printf '\\033]0;%s\\007\\033]2;%s\\007' {title_q} {title_q}; }}
__gssh_original_prompt_command=\"$PROMPT_COMMAND\"
PROMPT_COMMAND=\"${{__gssh_original_prompt_command:+$__gssh_original_prompt_command; }}__gssh_set_title\"
__gssh_set_title
trap 'rm -f \"$GSSH_RC_TMP\"' EXIT
"""
rc_q = shlex.quote(rc)
print(f"""if command -v bash >/dev/null 2>&1; then
    GSSH_RC_TMP=$(mktemp /tmp/gssh-rc.XXXXXX) || exit 1
    printf %s {rc_q} > "$GSSH_RC_TMP"
    export GSSH_RC_TMP
    exec bash --rcfile "$GSSH_RC_TMP" -i
else
    export TERM=xterm-256color
    export COLORTERM=truecolor
    printf '\\033]0;%s\\007\\033]2;%s\\007' {title_q} {title_q}
    exec "${{SHELL:-/bin/sh}}" -i
fi""")
PY
}

function _gssh_sshpass_run() {
    local ip="$1"
    local port="$2"
    local password="$3"
    shift 3
    local attempt=1
    local rc
    local sshpass_bin
    local tmp

    sshpass_bin="$(_gssh_sshpass)"
    [[ -z "$sshpass_bin" ]] && { echo "缺少 sshpass：brew install hudochenkov/sshpass/sshpass" >&2; return 1; }
    while (( attempt <= 2 )); do
        tmp="$(mktemp)"
        SSHPASS="$password" "$sshpass_bin" -e "$@" 2> >(tee "$tmp" >&2)
        rc=$?
        if grep -Eqi 'REMOTE HOST IDENTIFICATION HAS CHANGED|Offending .* key|Host key verification failed' "$tmp"; then
            rm -f "$tmp"
            _gssh_forget_host_key "$ip" "$port" || return 86
            (( attempt++ ))
            continue
        fi
        rm -f "$tmp"
        [[ "$rc" -eq 5 || "$rc" -eq 6 ]] && echo "认证失败：请检查 hosts.jsonl 中的用户名或密码。" >&2
        return "$rc"
    done
    echo "重试后仍然出现 host key 校验失败。" >&2
    return 86
}

function _gssh_host_key_failure_on_connect() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local tmp
    local matched

    if ! ssh-keygen -F "$ip" >/dev/null 2>&1 && ! ssh-keygen -F "[$ip]:$port" >/dev/null 2>&1; then
        return 1
    fi

    tmp="$(mktemp)"
    ssh -p "$port" \
        -o StrictHostKeyChecking=yes \
        -o BatchMode=yes \
        -o NumberOfPasswordPrompts=0 \
        "$user@$ip" true >/dev/null 2>"$tmp"
    grep -Eqi 'REMOTE HOST IDENTIFICATION HAS CHANGED|Offending .* key|Host key verification failed' "$tmp"
    matched=$?
    rm -f "$tmp"
    return "$matched"
}

function _gssh_transfer_run() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    shift 4
    local attempt=1
    local rc
    local sshpass_bin

    sshpass_bin="$(_gssh_sshpass)"
    [[ -z "$sshpass_bin" ]] && { echo "缺少 sshpass：brew install hudochenkov/sshpass/sshpass" >&2; return 1; }

    while (( attempt <= 2 )); do
        SSHPASS="$password" "$sshpass_bin" -e "$@"
        rc=$?
        [[ "$rc" -eq 0 ]] && return 0

        if _gssh_host_key_failure_on_connect "$ip" "$port" "$user"; then
            _gssh_forget_host_key "$ip" "$port" || return 86
            (( attempt++ ))
            continue
        fi

        [[ "$rc" -eq 5 || "$rc" -eq 6 ]] && echo "认证失败：请检查 hosts.jsonl 中的用户名或密码。" >&2
        return "$rc"
    done

    echo "重试后仍然出现 host key 校验失败。" >&2
    return 86
}

function _gssh_progress_pid_stop() {
    local pid="$1"
    local i
    [[ -n "$pid" ]] || return 0
    kill -TERM "$pid" >/dev/null 2>&1 || true
    for i in {1..10}; do
        kill -0 "$pid" >/dev/null 2>&1 || break
        sleep 0.1
    done
    kill -KILL "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
    printf '\n' >&2
}

function _gssh_watch_local_progress() {
    local watch_path="$1"
    local total_kb="${2:-0}"
    local baseline_kb="${3:-0}"
    local done_kb=0
    local current_kb=0
    local sleep_pid=""
    trap '[[ -n "$sleep_pid" ]] && kill "$sleep_pid" >/dev/null 2>&1; exit 0' TERM INT
    while true; do
        current_kb="$(_gssh_local_size_kb "$watch_path")"
        done_kb=$(( current_kb - baseline_kb ))
        (( done_kb < 0 )) && done_kb=0
        _gssh_progress_line "$done_kb" "$total_kb"
        sleep 2 &
        sleep_pid=$!
        wait "$sleep_pid" 2>/dev/null
        sleep_pid=""
    done
}

function _gssh_watch_remote_progress() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local remote_path="$5"
    local total_kb="${6:-0}"
    local baseline_kb="${7:-0}"
    local done_kb=0
    local current_kb=0
    local sleep_pid=""
    trap '[[ -n "$sleep_pid" ]] && kill "$sleep_pid" >/dev/null 2>&1; exit 0' TERM INT
    while true; do
        current_kb="$(_gssh_remote_size_kb "$ip" "$port" "$user" "$password" "$remote_path")"
        [[ -z "$current_kb" ]] && current_kb=0
        done_kb=$(( current_kb - baseline_kb ))
        (( done_kb < 0 )) && done_kb=0
        _gssh_progress_line "$done_kb" "$total_kb"
        sleep 2 &
        sleep_pid=$!
        wait "$sleep_pid" 2>/dev/null
        sleep_pid=""
    done
}

function _gssh_start_local_progress() {
    (_gssh_watch_local_progress "$@") &!
    progress_pid=$!
}

function _gssh_start_remote_progress() {
    (_gssh_watch_remote_progress "$@") &!
    progress_pid=$!
}

function _gssh_connect_host_json() {
    local host_json="$1"
    local ip user password port remote_cmd
    _gssh_load_host_fields "$host_json" || return 1
    [[ -z "$port" ]] && port="22"
    remote_cmd="$(_gssh_remote_title_command "$ip")"
    [[ "$GSSH_CLEAR_BEFORE_CONNECT" == "1" ]] && clear
    _gssh_set_title "$ip"
    echo "Connecting $user@$ip:$port ..."
    _gssh_sshpass_run "$ip" "$port" "$password" ssh -tt -p "$port" -o StrictHostKeyChecking=accept-new -o NumberOfPasswordPrompts=1 "$user@$ip" "$remote_cmd"
    _gssh_set_title "Ghostty"
}

function s() {
    _gssh_require || return 1
    local ip host_json
    ip="$(_gssh_select_ip "$1")" || return
    [[ -z "$ip" ]] && return
    host_json="$(_gssh_host_json "$ip")" || { echo "未找到主机记录：$ip" >&2; return 1; }
    _gssh_connect_host_json "$host_json"
}

function pwds() {
    _gssh_require || return 1
    local query="$1"
    local fzf_bin selected ip host_json user password port
    _gssh_migrate_once
    if [[ -z "$query" ]]; then
        _gssh_json auths
        return
    fi
    command -v pbcopy >/dev/null 2>&1 || { echo "缺少 pbcopy：pwds 目前使用 macOS 剪贴板。" >&2; return 1; }
    fzf_bin="$(_gssh_fzf)"
    selected="$(_gssh_json machine_creds | "$fzf_bin" --query="$query" --prompt="选择机器凭证 (将复制账号和密码) > " --layout=reverse --height=40% --border --header=$'IP\tUSER\tPORT\tPASSWORD')"
    [[ -z "$selected" ]] && return
    ip="${selected%%$'\t'*}"
    [[ -z "$ip" ]] && return
    host_json="$(_gssh_host_json "$ip")" || { echo "未找到主机记录：$ip" >&2; return 1; }
    _gssh_load_host_fields "$host_json" || return 1
    printf '%s\n%s' "$user" "$password" | pbcopy
    echo "已复制账号和密码到剪贴板：$user@$ip"
}

function nssh() {
    _gssh_require || return 1
    _gssh_migrate_once

    local ip fzf_bin auths fzf_prompt fzf_out pwd_query pwd_match selected_auth
    local user password port host_json

    ip="$1"
    if [[ -z "$ip" ]]; then
        print -n "新机器/更新机器 IP: "
        read ip
    fi
    [[ -z "$ip" ]] && { echo "IP 不能为空"; return 1; }

    fzf_bin="$(_gssh_fzf)"
    auths="$(_gssh_json auths)"
    fzf_prompt="选择已有凭证，或直接输入新凭证 (如 ubuntu|123456) > "
    if [[ -n "$auths" ]]; then
        fzf_out="$(printf '%s\n' "$auths" | "$fzf_bin" --prompt="$fzf_prompt" --print-query --layout=reverse --height=30% --border)"
    else
        fzf_out="$("$fzf_bin" --prompt="$fzf_prompt" --print-query --layout=reverse --height=30% --border < /dev/null)"
    fi

    pwd_query="$(echo "$fzf_out" | head -n 1)"
    pwd_match="$(echo "$fzf_out" | awk 'NR==2')"
    selected_auth="${pwd_match:-$pwd_query}"
    [[ -z "$selected_auth" ]] && { echo "凭证不能为空"; return 1; }

    if [[ "$selected_auth" == *" | "* ]]; then
        user="${selected_auth%% | *}"
        password="${selected_auth#* | }"
    elif [[ "$selected_auth" == *"|"* ]]; then
        user="${selected_auth%%|*}"
        password="${selected_auth#*|}"
    else
        user="root"
        password="$selected_auth"
    fi

    print -n "端口 (回车默认 22): "
    read port
    [[ -z "$port" ]] && port="22"

    _gssh_json upsert "$ip" "$user" "$password" "$port" || return 1
    echo "机器已成功归档/更新。"
    echo "正在连接..."
    host_json="$(_gssh_host_json "$ip")" || return 1
    _gssh_connect_host_json "$host_json"
}

function up() {
    _gssh_require || return 1
    local ip host_json user password port local_path remote_path rc total_kb watch_path baseline_kb progress_pid
    rc=1
    progress_pid=""
    ip="$(_gssh_select_ip "$1")" || return
    [[ -z "$ip" ]] && return
    host_json="$(_gssh_host_json "$ip")" || { echo "未找到主机记录：$ip" >&2; return 1; }
    _gssh_load_host_fields "$host_json" || return 1
    [[ -z "$port" ]] && port="22"

    local_path="$(_gssh_read_path "拖入[本地文件/文件夹]: ")"
    local_path="$(_gssh_clean_local_path "$local_path")"
    [[ -z "$local_path" ]] && { echo "本地路径不能为空"; return 1; }
    [[ ! -e "$local_path" ]] && { echo "本地路径不存在：$local_path"; return 1; }

    remote_path="$(_gssh_read_path "远端路径 (回车默认 /tmp): ")"
    [[ -z "$remote_path" ]] && remote_path="/tmp"
    remote_path="$(_gssh_clean_path "$remote_path")"

    total_kb="$(_gssh_local_size_kb "$local_path")"
    watch_path="$(_gssh_upload_target_path "$ip" "$port" "$user" "$password" "$local_path" "$remote_path")"
    baseline_kb="$(_gssh_remote_size_kb "$ip" "$port" "$user" "$password" "$watch_path")"
    [[ -z "$baseline_kb" ]] && baseline_kb=0

    printf '\nUpload:\n  local:  %s\n  remote: %s@%s:%s\n  size:   %s\n\nStarting scp...\n' "$local_path" "$user" "$ip" "$remote_path" "$(_gssh_human_kb "$total_kb")"
    {
        _gssh_start_remote_progress "$ip" "$port" "$user" "$password" "$watch_path" "$total_kb" "$baseline_kb"
        _gssh_transfer_run "$ip" "$port" "$user" "$password" scp -r -P "$port" -o StrictHostKeyChecking=accept-new -o NumberOfPasswordPrompts=1 "$local_path" "$user@$ip:$remote_path"
        rc=$?
    } always {
        _gssh_progress_pid_stop "$progress_pid"
    }
    [[ "$rc" -eq 0 ]] && _gssh_progress_line "$total_kb" "$total_kb" && printf '\n' >&2
    [[ "$rc" -eq 0 ]] && echo "上传完成。"
    return "$rc"
}

function down() {
    _gssh_require || return 1
    local ip host_json user password port remote_path local_path rc total_kb watch_path baseline_kb progress_pid
    rc=1
    progress_pid=""
    ip="$(_gssh_select_ip "$1")" || return
    [[ -z "$ip" ]] && return
    host_json="$(_gssh_host_json "$ip")" || { echo "未找到主机记录：$ip" >&2; return 1; }
    _gssh_load_host_fields "$host_json" || return 1
    [[ -z "$port" ]] && port="22"

    remote_path="$(_gssh_read_path "远程绝对路径: ")"
    remote_path="$(_gssh_clean_path "$remote_path")"
    [[ -z "$remote_path" ]] && { echo "远程路径不能为空"; return 1; }

    local_path="$(_gssh_read_path "本地目录 (回车默认 ~/Downloads): ")"
    [[ -z "$local_path" ]] && local_path="$HOME/Downloads"
    local_path="$(_gssh_clean_local_path "$local_path")"

    total_kb="$(_gssh_remote_size_kb "$ip" "$port" "$user" "$password" "$remote_path")"
    [[ -z "$total_kb" ]] && total_kb=0
    watch_path="$(_gssh_download_target_path "$remote_path" "$local_path")"
    baseline_kb="$(_gssh_local_size_kb "$watch_path")"

    printf '\nDownload:\n  remote: %s@%s:%s\n  local:  %s\n  size:   %s\n\nStarting scp...\n' "$user" "$ip" "$remote_path" "$local_path" "$(_gssh_human_kb "$total_kb")"
    {
        _gssh_start_local_progress "$watch_path" "$total_kb" "$baseline_kb"
        _gssh_transfer_run "$ip" "$port" "$user" "$password" scp -r -P "$port" -o StrictHostKeyChecking=accept-new -o NumberOfPasswordPrompts=1 "$user@$ip:$remote_path" "$local_path"
        rc=$?
    } always {
        _gssh_progress_pid_stop "$progress_pid"
    }
    [[ "$rc" -eq 0 ]] && _gssh_progress_line "$total_kb" "$total_kb" && printf '\n' >&2
    [[ "$rc" -eq 0 ]] && echo "下载完成。"
    return "$rc"
}

function gssh() {
    s "$@"
}

function gssh-add() {
    nssh "$@"
}

function gup() {
    up "$@"
}

function gdown() {
    down "$@"
}

function gpwds() {
    pwds "$@"
}
