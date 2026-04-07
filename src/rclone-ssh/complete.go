package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// commandRunner executes an external command and returns its stdout.
type commandRunner func(name string, args ...string) (string, error)

// sshConfigReader returns the raw contents of an SSH config file.
type sshConfigReader func() (string, error)

func defaultCommandRunner(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return "", err
	}
	return string(out), nil
}

func defaultSSHConfigReader() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile(filepath.Join(home, ".ssh", "config"))
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// handleComplete is the entry point for the __complete subcommand.
func handleComplete(args []string) int {
	return handleCompleteWith(args, defaultCommandRunner, defaultSSHConfigReader)
}

// handleCompleteWith routes the completion request to the appropriate handler.
func handleCompleteWith(args []string, run commandRunner, readConfig sshConfigReader) int {
	last := lastArg(args)

	switch {
	case isHostPath(last):
		// Branch A: Remote file listing via SSH
		completeRemoteFiles(last, run)
		return 0
	case isRemotePosition(args):
		// Branch B: List SSH hosts and rclone remotes
		completeHosts(run, readConfig)
		return 0
	default:
		// Branch C: Forward to rclone for subcommands and flags
		return forwardToRclone(args)
	}
}

// shQuote wraps a string in single quotes, escaping existing single quotes,
// so it can be safely passed to a POSIX shell.
func shQuote(s string) string {
	if s == "" {
		return ""
	}
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// completeRemoteFiles queries a remote host via SSH for directory contents.
// Uses raw ssh with ControlMaster for near-zero latency.
func completeRemoteFiles(word string, run commandRunner) {
	host, pathPrefix := splitHostPath(word)
	glob := shQuote(pathPrefix) + "*"

	out, err := run("ssh", host, "command", "ls", "-d1FL", "--", glob)
	if err != nil {
		fmt.Println(":1") // Emit error directive
		return
	}

	for _, entry := range strings.Split(strings.TrimSpace(out), "\n") {
		if entry != "" {
			fmt.Printf("%s:%s\n", host, entry)
		}
	}

	fmt.Println(":2") // Emit noSpace directive
}

// completeHosts prints available SSH hosts and configured rclone remotes.
func completeHosts(run commandRunner, readConfig sshConfigReader) {
	hosts := getSSHConfigHosts(readConfig)
	for _, h := range hosts {
		fmt.Printf("%s:\n", h)
	}

	if rcloneOut, err := run("rclone", "listremotes"); err == nil {
		for _, remote := range strings.Split(strings.TrimSpace(rcloneOut), "\n") {
			if remote != "" {
				fmt.Printf("%s\n", remote)
			}
		}
	}

	fmt.Println(":2") // Emit noSpace directive
}

// forwardToRclone proxies the completion request to the system's rclone binary.
func forwardToRclone(args []string) int {
	cmd := exec.Command("rclone", append([]string{"__complete"}, args...)...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return 1
	}
	return cmd.ProcessState.ExitCode()
}

// getSSHConfigHosts extracts defined host aliases from the SSH configuration.
func getSSHConfigHosts(readConfig sshConfigReader) []string {
	raw, err := readConfig()
	if err != nil {
		return nil
	}
	return parseSSHConfigHosts(raw)
}

// parseSSHConfigHosts extracts concrete hostnames from SSH config contents.
// Skips wildcards (*) and negations (!), matching zsh's native behavior.
func parseSSHConfigHosts(raw string) []string {
	seen := map[string]bool{}
	scanner := bufio.NewScanner(strings.NewReader(raw))

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		var key, value string
		if idx := strings.IndexByte(line, '='); idx >= 0 {
			key = strings.TrimSpace(line[:idx])
			value = strings.TrimSpace(line[idx+1:])
		} else {
			parts := strings.SplitN(line, " ", 2)
			if len(parts) != 2 {
				parts = strings.SplitN(line, "\t", 2)
			}
			if len(parts) != 2 {
				continue
			}
			key = parts[0]
			value = parts[1]
		}

		if !strings.EqualFold(key, "Host") {
			continue
		}

		for _, pattern := range strings.Fields(value) {
			if strings.ContainsAny(pattern, "*?") || strings.HasPrefix(pattern, "!") || pattern == "" {
				continue
			}
			seen[pattern] = true
		}
	}

	hosts := make([]string, 0, len(seen))
	for h := range seen {
		hosts = append(hosts, h)
	}
	sort.Strings(hosts)
	return hosts
}

// isHostPath checks if the word conforms to "host:path" or "host:" syntax.
func isHostPath(word string) bool {
	if strings.HasPrefix(word, "-") || strings.HasPrefix(word, ":") {
		return false
	}
	parts := strings.SplitN(word, ":", 2)
	// Ensure colon is present and host segment isn't empty
	return len(parts) == 2 && len(parts[0]) > 0
}

// isRemotePosition checks if the context indicates a positional argument.
func isRemotePosition(args []string) bool {
	return len(args) >= 2 && !strings.HasPrefix(lastArg(args), "-")
}

// lastArg returns the final element from a slice, or empty string if nil/empty.
func lastArg(args []string) string {
	if len(args) == 0 {
		return ""
	}
	return args[len(args)-1]
}

// splitHostPath extracts the host and path components from a "host:path" string.
func splitHostPath(word string) (host, path string) {
	parts := strings.SplitN(word, ":", 2)
	if len(parts) == 2 {
		return parts[0], parts[1]
	}
	return word, ""
}
