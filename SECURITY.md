# Security Policy

## English

gssh-flow is designed for personal/internal development and test environments where machines are frequently rebuilt, snapshotted, or reused.

Important security facts:

- `hosts.jsonl` stores SSH passwords in plaintext on your local machine.
- The installer sets `~/.config/gssh-flow` to `700` and `hosts.jsonl` to `600`, but any process running as your user can still read the file.
- gssh-flow uses `sshpass -e`, so passwords are not passed as command-line arguments, but they are briefly available as an environment variable for the `sshpass` process.
- gssh-flow uses `StrictHostKeyChecking=accept-new`: new host keys are accepted automatically on first connection, while changed known host keys are still blocked and require explicit confirmation before removal.
- This tool is not recommended for high-security production systems, shared workstations, or regulated environments.

Never commit or share your real `hosts.jsonl`.

## 中文

gssh-flow 面向个人/内部研发测试环境，尤其适合机器经常重装、快照回滚、IP 复用的场景。

重要安全边界：

- `hosts.jsonl` 会在本机明文保存 SSH 密码。
- 安装脚本会把 `~/.config/gssh-flow` 设置为 `700`，把 `hosts.jsonl` 设置为 `600`，但任何以你当前用户权限运行的进程仍然可能读取它。
- gssh-flow 使用 `sshpass -e`，密码不会出现在命令参数里，但会短暂存在于 `sshpass` 进程环境变量中。
- gssh-flow 使用 `StrictHostKeyChecking=accept-new`：首次连接新主机会自动接受 host key；已知主机 key 变化仍会被拦截，并要求确认后才删除旧记录。
- 不建议用于高安全生产服务器、多人共享电脑或强审计环境。

不要提交或分享真实的 `hosts.jsonl`。
