# gssh-flow

> 中文说明在前，English follows.

gssh-flow 是一个轻量的终端机器管理工作流：用 `fzf` 搜索主机，用 `sshpass -e` 自动输入密码，用 JSON Lines 管理机器凭证，并在 Ghostty / 普通终端里完成 SSH 登录和 SCP 上传下载。

它适合内网研发、测试、快照频繁恢复、机器经常重装的环境。

当前版本面向 macOS + zsh。`pwds` 使用 macOS 的 `pbcopy`，安装脚本会写入 `~/.zshrc` 和 `~/.zprofile`。

## 功能特性

- `s`：fzf 搜索 IP 并 SSH 登录
- `nssh`：新增或更新机器凭证
- `up`：上传本地文件/目录到远端，默认 `/tmp`
- `down`：从远端下载文件/目录到本地，默认 `~/Downloads`
- `pwds`：选择凭证并只复制密码到 macOS 剪贴板
- JSONL 凭证库，支持密码包含空格、`|`、引号、中文等字符
- 主机列表只展示 IP，不展示密码
- 使用 `sshpass -e`，避免密码出现在命令参数中
- 使用真实 `~/.ssh/known_hosts`
- 使用 `StrictHostKeyChecking=accept-new`：首次连接自动接受新 host key，host key 变化仍会拦截
- Ghostty 中连接后标题显示当前 IP
- 远端 shell 注入 `TERM=xterm-256color` 和 `COLORTERM=truecolor`，减少 SSH 后颜色退化

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/Skies-syx/gssh-flow/main/install.sh | bash
```

安装完成后执行：

```bash
source ~/.zshrc
```

或者重新打开终端。

### 依赖

macOS:

```bash
brew install fzf
brew install hudochenkov/sshpass/sshpass
```

还需要：

```text
python3
ssh
scp
ssh-keygen
pbcopy
```

安装脚本会检查依赖，但不会静默安装依赖。

## 快速开始

新增或更新机器：

```bash
nssh 10.0.0.10
```

按提示输入凭证：

```text
root|your_password
```

端口默认 `22`，直接回车即可。

搜索并连接：

```bash
s
```

或带查询：

```bash
s 10.0.0
s 10
```

上传：

```bash
up
```

下载：

```bash
down
```

复制密码：

```bash
pwds
```

## 命令

| 命令 | 说明 |
| --- | --- |
| `s [query]` | 搜索主机并 SSH 登录 |
| `nssh [ip]` | 新增或更新主机，完成后自动连接 |
| `up [query]` | 选择主机并上传文件/目录 |
| `down [query]` | 选择主机并下载文件/目录 |
| `pwds` | 选择凭证并复制密码 |

同时提供长命令别名：

| 短命令 | 长命令 |
| --- | --- |
| `s` | `gssh` |
| `nssh` | `gssh-add` |
| `up` | `gup` |
| `down` | `gdown` |
| `pwds` | `gpwds` |

可选环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `GSSH_CLEAR_BEFORE_CONNECT` | `0` | 设为 `1` 时，SSH 登录前清屏 |
| `GSSH_AUTO_MIGRATE_LEGACY` | `0` | 设为 `1` 时，命令执行前允许从旧 `~/.ssh/hosts.txt` 迁移 |

## 数据格式

凭证保存在：

```text
~/.config/gssh-flow/hosts.jsonl
```

每行一台机器：

```json
{"ip":"10.0.0.10","user":"root","password":"your_password","port":22}
{"ip":"10.0.0.11","user":"ubuntu","password":"another_password","port":22}
```

权限建议：

```bash
chmod 700 ~/.config/gssh-flow
chmod 600 ~/.config/gssh-flow/hosts.jsonl
```

不要把真实 `hosts.jsonl` 提交到 Git 或同步到网盘。

### 从旧 `hosts.txt` 迁移

如果你以前使用过块状格式：

```text
root|password|22
10.0.0.10
10.0.0.11
```

可以临时开启迁移：

```bash
gssh-migrate-legacy
```

也可以在下一次执行命令时临时允许迁移：

```bash
GSSH_AUTO_MIGRATE_LEGACY=1 s
```

默认不会自动读取旧 `~/.ssh/hosts.txt`，避免误迁移无关文件。迁移后继续使用 `hosts.jsonl`。

如果旧 `hosts.txt` 和现有 `hosts.jsonl` 有相同 IP，保留现有 `hosts.jsonl` 记录，旧数据只补充缺失 IP。

## Ghostty 建议配置

如果你使用 Ghostty，建议在配置中加入：

```ini
shell-integration = detect
shell-integration-features = ssh-env,ssh-terminfo
```

这有助于降低 SSH 到旧 Linux 机器后 `TERM=xterm-ghostty` 不被识别导致的颜色问题。

gssh-flow 自身也会在远端交互 shell 中设置：

```bash
export TERM=xterm-256color
export COLORTERM=truecolor
```

## Host key 行为

gssh-flow 使用：

```bash
-o StrictHostKeyChecking=accept-new
```

含义：

- 第一次连接新主机时，自动接受 host key 并写入 `~/.ssh/known_hosts`
- 后续连接会正常校验 host key
- 如果 host key 变化，会被拦截

当 host key 变化时，gssh-flow 会询问：

```text
确认这是机器重装/快照回滚/IP 复用，并删除旧 known_hosts 记录？输入 yes 确认:
```

只有输入 `yes` 才会执行：

```bash
ssh-keygen -R "$ip"
ssh-keygen -R "[$ip]:$port"
```

然后自动重试。

## 上传和下载

`up` 使用 `scp -r` 上传：

```text
默认远端路径：/tmp
```

`down` 使用 `scp -r` 下载：

```text
默认本地路径：~/Downloads
```

路径输入支持常见的 Finder 拖入格式，会自动去掉首尾引号、尾部空格和粘贴带来的换行。

传输时会显示汇总进度：

- 下载时，按本地目标文件/目录增长量估算进度
- 上传时，每 2 秒通过 SSH 查询一次远端目标大小来估算进度
- 小文件可能瞬间完成，只看到最终 `100%`
- 远端路径不存在、权限不足或远端缺少 `du` 时，仍会继续执行 `scp`，但总大小可能显示为 `0K`

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/Skies-syx/gssh-flow/main/uninstall.sh | bash
```

卸载脚本会移除 shell source 行和 `workflow.zsh`，但默认保留：

```text
~/.config/gssh-flow/hosts.jsonl
```

避免误删你的凭证。

## 安全说明

gssh-flow 面向研发/测试环境，不建议用于高安全生产环境。

重要边界：

- `hosts.jsonl` 明文保存密码
- `sshpass -e` 避免密码出现在命令参数里，但密码会短暂存在于进程环境变量中
- `accept-new` 会自动信任首次连接的新 host key
- host key 变化仍会被拦截

更多信息见 [SECURITY.md](SECURITY.md)。

## 常见问题

### `s: command not found`

执行：

```bash
source ~/.zshrc
```

如果是 Ghostty 下拉终端：

```bash
source ~/.zprofile
```

或者重新打开终端。

### 缺少 fzf

```bash
brew install fzf
```

### 缺少 sshpass

```bash
brew install hudochenkov/sshpass/sshpass
```

### 登录后 Vim 还是不好看

Ghostty 只能保证终端颜色能力，远端 Vim 仍需要远端自己的 `.vimrc` 和主题。

### `tail -f` 日志没有颜色

`tail -f` 默认只原样输出日志。除非日志本身带 ANSI 颜色，否则 Ghostty 不会像某些 GUI SSH 客户端那样自动按 IP/URL/关键词上色。

---

# gssh-flow English

gssh-flow is a tiny terminal-first SSH workflow. It uses `fzf` for host search, `sshpass -e` for password entry, JSON Lines for host storage, and `scp` for file transfer.

It is designed for internal development/test environments where machines are frequently rebuilt, snapshotted, or reused.

The current version targets macOS + zsh. `pwds` uses macOS `pbcopy`, and the installer writes to `~/.zshrc` and `~/.zprofile`.

## Features

- `s`: search hosts with fzf and SSH into one
- `nssh`: add or update a host
- `up`: upload a local file/directory to a remote host, default remote path `/tmp`
- `down`: download a remote file/directory, default local path `~/Downloads`
- `pwds`: pick a credential and copy only the password to the macOS clipboard
- JSONL host database
- IP-only host list; passwords are not shown in host search
- Password-based SSH via `sshpass -e`
- Real `~/.ssh/known_hosts`
- `StrictHostKeyChecking=accept-new`: accept new host keys, block changed known keys
- Ghostty-friendly title support: connected sessions show the remote IP
- Remote shell gets `TERM=xterm-256color` and `COLORTERM=truecolor`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Skies-syx/gssh-flow/main/install.sh | bash
```

Then run:

```bash
source ~/.zshrc
```

or restart your terminal.

## Dependencies

On macOS:

```bash
brew install fzf
brew install hudochenkov/sshpass/sshpass
```

Also required:

```text
python3
ssh
scp
ssh-keygen
pbcopy
```

The installer checks dependencies but does not silently install them.

## Quick Start

Add or update a host:

```bash
nssh 10.0.0.10
```

Enter a credential:

```text
root|your_password
```

Connect:

```bash
s
```

Upload:

```bash
up
```

Download:

```bash
down
```

Copy a password:

```bash
pwds
```

Long command aliases are also available:

| Short | Long |
| --- | --- |
| `s` | `gssh` |
| `nssh` | `gssh-add` |
| `up` | `gup` |
| `down` | `gdown` |
| `pwds` | `gpwds` |

Optional environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `GSSH_CLEAR_BEFORE_CONNECT` | `0` | Set to `1` to clear the terminal before SSH login |
| `GSSH_AUTO_MIGRATE_LEGACY` | `0` | Set to `1` to allow migration from the old `~/.ssh/hosts.txt` before command execution |

## Data Format

Hosts are stored at:

```text
~/.config/gssh-flow/hosts.jsonl
```

One JSON object per line:

```json
{"ip":"10.0.0.10","user":"root","password":"your_password","port":22}
```

Protect it:

```bash
chmod 700 ~/.config/gssh-flow
chmod 600 ~/.config/gssh-flow/hosts.jsonl
```

Never commit or share your real `hosts.jsonl`.

### Migrating from old `hosts.txt`

If you used the older block format:

```text
root|password|22
10.0.0.10
10.0.0.11
```

Run a one-time migration with:

```bash
gssh-migrate-legacy
```

Or allow migration for the next command:

```bash
GSSH_AUTO_MIGRATE_LEGACY=1 s
```

By default, gssh-flow does not read `~/.ssh/hosts.txt`, so it will not accidentally import unrelated files. After migration, `hosts.jsonl` is the source of truth.

If old `hosts.txt` and existing `hosts.jsonl` contain the same IP, the existing `hosts.jsonl` record is kept. Legacy migration only fills missing IPs.

## Upload and Download

`up` and `down` use `scp -r`.

- Upload default remote path: `/tmp`
- Download default local path: `~/Downloads`
- Finder-dropped paths and pasted paths with surrounding quotes, trailing spaces, or line breaks are cleaned automatically

Transfers show aggregate progress:

- Downloads estimate progress from the growing local target
- Uploads query the remote target size over SSH every 2 seconds
- Small files may finish immediately, so you may only see the final `100%`
- If the remote path is missing, inaccessible, or `du` is unavailable, `scp` still runs but the total size may show as `0K`

## Security Notes

gssh-flow is not recommended for high-security production systems.

- Passwords are stored in plaintext JSONL.
- `sshpass -e` avoids command-line password exposure, but the password is briefly available as an environment variable.
- `StrictHostKeyChecking=accept-new` trusts first-use host keys automatically.
- Changed known host keys are still blocked and require confirmation before removal.

See [SECURITY.md](SECURITY.md).

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/Skies-syx/gssh-flow/main/uninstall.sh | bash
```

Your `hosts.jsonl` is kept by default.
