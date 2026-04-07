# rclone-ssh

`rclone-ssh` is a Go-based, drop-in wrapper over `rclone` that seamlessly integrates your native OpenSSH configuration (`~/.ssh/config`) with rclone's powerful file transfer capabilities.

With `rclone-ssh`, you can interact with any SSH server just like you would with `scp` or `rsync`, completely bypassing the need to manually define remote environments in `rclone.conf`.

## Why rclone-ssh?

Normally, `rclone` requires you to explicitly configure an SFTP remote for every single destination server. `rclone-ssh` dynamically intercepts commands like `rclone-ssh copy myhost:/path /local` and translates them into rclone's on-the-fly connection strings (e.g., `:sftp,host=...`), automatically pulling the necessary ports, users, keys, and proxy mappings directly from your `~/.ssh/config`.

## Features

- **Zero-Config Remote Backends:** Automatically parses `~/.ssh/config` (via `ssh -G`) to resolve `HostName`, `User`, `Port`, and `IdentityFile` directives dynamically.
- **Proxy Translation:** Automatically parses `ProxyCommand` directives containing `connect-proxy`, `nc`, or `ncat` and translates them into native `rclone` flags (e.g., `--sftp-socks-proxy` and `--sftp-http-proxy`).
- **ControlMaster Speed:** Operates effortlessly alongside your existing SSH multiplexing (`ControlMaster`) for extremely low latency.
- **Native Shell Autocompletion:** Implements the hidden `__complete` subcommand to hook seamlessly into `zsh` and `bash` tab completions:
  - **SSH Host Completion**: Instantly auto-completes hostnames defined in your `ssh_config`.
  - **Remote File Completion**: Uses raw `ssh` for remote file completion matching (`ls -d1FL`), drastically outperforming `rclone`'s native SFTP backend file listing.
  - **Pass-through Subcommands**: Transparently forwards standard `rclone` subcommands (`copy`, `sync`, `move`) and arguments (`--progress`, `--dry-run`) back to the underlying `rclone` binary.

## Usage

Simply substitute the `rclone` command with `rclone-ssh` in any context when transferring between local paths and SFTP hosts.

```bash
# Copy a local file to a remote server defined in ~/.ssh/config
rclone-ssh copy ./local-file.txt my-server:/remote/path/

# Sync a remote directory to your local machine using an HTTP/SOCKS5 ProxyCommand
rclone-ssh sync my-secure-server:/app/logs/ ./local-logs/ --progress

# Interact with known rclone remotes seamlessly (fallback works perfectly)
rclone-ssh listremotes
```

## Setup & Compilation

You will require a system with Go installed.

```bash
# Build the binary
go build -o rclone-ssh .

# Move it to your PATH
sudo mv rclone-ssh /usr/local/bin/

# Initialize zsh autocompletion
compdef _rclone rclone-ssh
```

## How It Works

1. **Args Interceptor**: `rclone-ssh` parses the command line inputs. If it detects a request like `my-server:/data`, it pauses execution.
2. **Resolver**: It invokes `ssh -G my-server` to resolve the underlying SSH connection properties and maps them to a dynamic `rclone` remote like `:sftp,host=10.0.0.1,port=2222:`...
3. **Execution Replace**: Using `syscall.Exec`, the wrapper seamlessly replaces its own process with the system's `rclone` binary, executing the perfectly formed string with near-zero overhead.
4. **Shell Completion**: If `rclone-ssh` intercepts the special `__complete` arg from shell autocompletion hooks, it responds to the completion request natively based on context.
