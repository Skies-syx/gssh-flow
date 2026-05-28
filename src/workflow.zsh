# gssh-flow: fzf-powered SSH workflow for Ghostty and terminal-first users.
# Safe-mode only: uses ~/.ssh/known_hosts and sshpass -e password entry.

if [[ -n "$GSSH_FLOW_LOADED" ]] && typeset -f s >/dev/null 2>&1; then
    return 0
fi
GSSH_FLOW_LOADED=1

export GSSH_HOME="${GSSH_HOME:-$HOME/.config/gssh-flow}"
export GSSH_HOSTS_FILE="${GSSH_HOSTS_FILE:-$GSSH_HOME/hosts.jsonl}"
export GSSH_LEGACY_HOSTS_FILE="${GSSH_LEGACY_HOSTS_FILE:-$HOME/.ssh/hosts.txt}"
export GSSH_AUTO_MIGRATE_LEGACY="${GSSH_AUTO_MIGRATE_LEGACY:-0}"

function _gssh_bin() {
    local name="$1"
    local fallback="$2"
    local bin
    bin=$(command -v "$name" 2>/dev/null) && { echo "$bin"; return 0; }
    [[ -n "$fallback" && -x "$fallback" ]] && echo "$fallback"
}

function _gssh_fzf() {
    _gssh_bin fzf /opt/homebrew/bin/fzf
}

function _gssh_sshpass() {
    _gssh_bin sshpass /opt/homebrew/bin/sshpass
}

function _gssh_python() {
    _gssh_bin python3 /usr/bin/python3
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
    return "$missing"
}

function _gssh_prepare() {
    mkdir -p "$GSSH_HOME"
    [[ -f "$GSSH_HOSTS_FILE" ]] || : > "$GSSH_HOSTS_FILE"
    chmod 700 "$GSSH_HOME" 2>/dev/null
    chmod 600 "$GSSH_HOSTS_FILE" 2>/dev/null
}

function _gssh_clean_path() {
    local p="$1"
    p="${p//$'\r'/}"
    p="${p//$'\n'/}"
    p="${p% }"
    p="${p#\'}"
    p="${p%\'}"
    p="${p#\"}"
    p="${p%\"}"
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
    [[ -f "$GSSH_HOSTS_FILE" && -s "$GSSH_HOSTS_FILE" ]] && return 0
    [[ -f "$GSSH_LEGACY_HOSTS_FILE" ]] || return 0
    _gssh_json migrate "$GSSH_LEGACY_HOSTS_FILE"
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
        if grep -Eqi 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed' "$tmp"; then
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

function _gssh_connect_host_json() {
    local host_json="$1"
    local ip user password port remote_cmd
    ip="$(_gssh_host_field "$host_json" ip)"
    user="$(_gssh_host_field "$host_json" user)"
    password="$(_gssh_host_field "$host_json" password)"
    port="$(_gssh_host_field "$host_json" port)"
    [[ -z "$port" ]] && port="22"
    remote_cmd="$(_gssh_remote_title_command "$ip")"
    clear
    _gssh_set_title "$ip"
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
    local fzf_bin selected pass
    fzf_bin="$(_gssh_fzf)"
    _gssh_migrate_once
    selected="$(_gssh_json auths | "$fzf_bin" --prompt="选择凭证 (将自动复制密码) > " --layout=reverse --height=30% --border)"
    [[ -z "$selected" ]] && return
    pass="${selected#* | }"
    echo -n "$pass" | pbcopy
    echo "密码已复制到剪贴板。"
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
    local ip host_json user password port local_path remote_path rc
    ip="$(_gssh_select_ip "$1")" || return
    [[ -z "$ip" ]] && return
    host_json="$(_gssh_host_json "$ip")" || { echo "未找到主机记录：$ip" >&2; return 1; }
    user="$(_gssh_host_field "$host_json" user)"
    password="$(_gssh_host_field "$host_json" password)"
    port="$(_gssh_host_field "$host_json" port)"
    [[ -z "$port" ]] && port="22"

    local_path="$(_gssh_read_path "拖入[本地文件/文件夹]: ")"
    local_path="$(_gssh_clean_path "$local_path")"
    [[ -z "$local_path" ]] && { echo "本地路径不能为空"; return 1; }

    remote_path="$(_gssh_read_path "远端路径 (回车默认 /tmp): ")"
    [[ -z "$remote_path" ]] && remote_path="/tmp"
    remote_path="$(_gssh_clean_path "$remote_path")"

    printf '\n上传中...\n'
    _gssh_sshpass_run "$ip" "$port" "$password" scp -r -P "$port" -o StrictHostKeyChecking=accept-new -o NumberOfPasswordPrompts=1 "$local_path" "$user@$ip:$remote_path"
    rc=$?
    [[ "$rc" -eq 0 ]] && echo "上传完成。"
    return "$rc"
}

function down() {
    _gssh_require || return 1
    local ip host_json user password port remote_path local_path rc
    ip="$(_gssh_select_ip "$1")" || return
    [[ -z "$ip" ]] && return
    host_json="$(_gssh_host_json "$ip")" || { echo "未找到主机记录：$ip" >&2; return 1; }
    user="$(_gssh_host_field "$host_json" user)"
    password="$(_gssh_host_field "$host_json" password)"
    port="$(_gssh_host_field "$host_json" port)"
    [[ -z "$port" ]] && port="22"

    remote_path="$(_gssh_read_path "远程绝对路径: ")"
    remote_path="$(_gssh_clean_path "$remote_path")"
    [[ -z "$remote_path" ]] && { echo "远程路径不能为空"; return 1; }

    local_path="$(_gssh_read_path "本地目录 (回车默认 ~/Downloads): ")"
    [[ -z "$local_path" ]] && local_path="$HOME/Downloads"
    local_path="$(_gssh_clean_path "$local_path")"

    printf '\n下载中...\n'
    _gssh_sshpass_run "$ip" "$port" "$password" scp -r -P "$port" -o StrictHostKeyChecking=accept-new -o NumberOfPasswordPrompts=1 "$user@$ip:$remote_path" "$local_path"
    rc=$?
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

_gssh_migrate_once >/dev/null 2>&1
