package main

import (
	"bufio"
	"fmt"
	"os/exec"
	"strings"
)

// ResolvedHost holds SSH connection parameters extracted from ssh -G.
type ResolvedHost struct {
	Host          string // HostName (resolved IP or FQDN)
	User          string
	Port          string
	IdentityFiles []string // all IdentityFile entries, in order
	ProxyCommand  string   // empty if none or "none"
}

// ResolveSSH invokes ssh -G to resolve the effective configuration for
// a given hostname. All parsing — Include directives, Match blocks,
// wildcards — is delegated to the ssh binary.
func ResolveSSH(hostname string) (*ResolvedHost, error) {
	return resolveSSHWith(hostname, func(h string) (string, error) {
		out, err := exec.Command("ssh", "-G", h).Output()
		if err != nil {
			return "", fmt.Errorf("ssh -G %s: %w", h, err)
		}
		return string(out), nil
	})
}

// resolveSSHWith accepts a custom runner so tests can inject fixture
// output without invoking ssh.
func resolveSSHWith(hostname string, runner func(string) (string, error)) (*ResolvedHost, error) {
	raw, err := runner(hostname)
	if err != nil {
		return nil, err
	}
	return parseSSHGOutput(raw)
}

// parseSSHGOutput parses the "key value" lines emitted by ssh -G.
func parseSSHGOutput(raw string) (*ResolvedHost, error) {
	r := &ResolvedHost{}
	scanner := bufio.NewScanner(strings.NewReader(raw))

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, " ", 2)
		if len(parts) != 2 {
			continue
		}

		switch strings.ToLower(parts[0]) {
		case "hostname":
			r.Host = parts[1]
		case "user":
			r.User = parts[1]
		case "port":
			r.Port = parts[1]
		case "identityfile":
			r.IdentityFiles = append(r.IdentityFiles, parts[1])
		case "proxycommand":
			if parts[1] != "none" {
				r.ProxyCommand = parts[1]
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("parsing ssh -G output: %w", err)
	}
	if r.Host == "" {
		return nil, fmt.Errorf("ssh -G returned no hostname")
	}
	return r, nil
}
