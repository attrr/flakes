package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// sshResolver resolves an SSH hostname to connection parameters.
// Production uses ResolveSSH; tests inject mocks.
type sshResolver func(hostname string) (*ResolvedHost, error)

// remoteListFunc returns the set of already-configured rclone remotes.
type remoteListFunc func() (map[string]bool, error)

// RewriteArgs scans args for host:path references, resolves each via
// SSH config, and rewrites them to rclone's on-the-fly :sftp backend.
func RewriteArgs(args []string) ([]string, error) {
	return rewriteArgsWith(args, ResolveSSH, listRcloneRemotes)
}

// rewriteArgsWith is the testable core with injectable dependencies.
func rewriteArgsWith(args []string, resolve sshResolver, listRemotes remoteListFunc) ([]string, error) {
	remotes, err := listRemotes()
	if err != nil {
		remotes = map[string]bool{}
		fmt.Fprintf(os.Stderr, "rclone-ssh: warning: could not list rclone remotes: %v\n", err)
	}

	out := make([]string, 0, len(args))

	for _, arg := range args {
		// Pass flags through unchanged. We deliberately do not try to
		// consume flag values: rclone flags use --key=value form, and
		// bare values after flags won't match the host:path pattern.
		if strings.HasPrefix(arg, "-") {
			out = append(out, arg)
			continue
		}

		// Already an on-the-fly backend (e.g. :sftp,host=...:path)
		if strings.HasPrefix(arg, ":") {
			out = append(out, arg)
			continue
		}

		parts := strings.SplitN(arg, ":", 2)
		if len(parts) != 2 || parts[0] == "" {
			out = append(out, arg)
			continue
		}

		name := parts[0]
		path := parts[1]

		// Single-letter prefix is a Windows drive letter, not a remote.
		if len(name) == 1 {
			out = append(out, arg)
			continue
		}

		// Known rclone remote — pass through to rclone as-is.
		if remotes[name+":"] || remotes[name] {
			out = append(out, arg)
			continue
		}

		// Resolve via SSH config; fall back to pass-through on failure.
		resolved, err := resolve(name)
		if err != nil {
			fmt.Fprintf(os.Stderr, "rclone-ssh: warning: could not resolve SSH host %q: %v (passing through)\n", name, err)
			out = append(out, arg)
			continue
		}

		rewritten, err := buildSFTPBackend(resolved, path, name)
		if err != nil {
			fmt.Fprintf(os.Stderr, "rclone-ssh: warning: %v (passing through)\n", err)
			out = append(out, arg)
			continue
		}
		out = append(out, rewritten)
	}

	return out, nil
}

// buildSFTPBackend produces a :sftp,key=val,...:path connection string
// from resolved SSH config. Values containing special characters are
// quoted to avoid ambiguity with rclone's connection-string separators.
func buildSFTPBackend(r *ResolvedHost, path string, originalHost string) (string, error) {
	params := []string{
		fmt.Sprintf("host=%s", r.Host),
	}

	if r.User != "" {
		params = append(params, fmt.Sprintf("user=%s", r.User))
	}
	if r.Port != "" && r.Port != "22" {
		params = append(params, fmt.Sprintf("port=%s", r.Port))
	}

	// Use the first identity file that exists on disk. ssh -G may
	// list defaults (e.g. ~/.ssh/id_rsa) even when they are absent.
	for _, kf := range r.IdentityFiles {
		if strings.HasPrefix(kf, "~/") {
			if home, err := os.UserHomeDir(); err == nil {
				kf = home + kf[1:]
			}
		}
		if _, err := os.Stat(kf); err == nil {
			params = append(params, fmt.Sprintf("key_file=%s", kf))
			break
		}
	}

	params = append(params, "key_use_agent=true")

	// Supply defaults so rclone skips auto-detection (which emits
	// "Can't save config" notices on ephemeral on-the-fly backends).
	params = append(params, "shell_type=unix", "md5sum_command=md5sum", "sha1sum_command=sha1sum")

	if r.ProxyCommand != "" {
		if proxy := ParseProxyCommand(r.ProxyCommand); proxy != nil {
			name, value := proxy.RcloneProxyFlag()
			params = append(params, fmt.Sprintf("%s=%s", name, value))
		} else {
			fmt.Fprintf(os.Stderr, "rclone-ssh: warning: unsupported ProxyCommand for host %q: %s\n", originalHost, r.ProxyCommand)
		}
	}

	return fmt.Sprintf(":sftp,%s:%s", joinParams(params), path), nil
}

// quoteValue wraps v in double quotes when it contains characters that
// conflict with rclone's connection-string grammar (, : " or space).
func quoteValue(v string) string {
	if strings.ContainsAny(v, ",:\" ") {
		return fmt.Sprintf("%q", v)
	}
	return v
}

// joinParams serialises key=value pairs into a comma-separated string,
// quoting values that contain rclone connection-string metacharacters.
func joinParams(params []string) string {
	quoted := make([]string, len(params))
	for i, param := range params {
		kv := strings.SplitN(param, "=", 2)
		if len(kv) == 2 {
			quoted[i] = kv[0] + "=" + quoteValue(kv[1])
		} else {
			quoted[i] = param
		}
	}
	return strings.Join(quoted, ",")
}

// listRcloneRemotes queries rclone for configured remotes (e.g. "gdrive:").
func listRcloneRemotes() (map[string]bool, error) {
	cmd := exec.Command("rclone", "listremotes")
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	remotes := map[string]bool{}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			remotes[line] = true
		}
	}
	return remotes, nil
}
