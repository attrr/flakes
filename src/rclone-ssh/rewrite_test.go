package main

import (
	"fmt"
	"os"
	"strings"
	"testing"
)

// mockResolver returns a fixed ResolvedHost for known hosts, error for unknown.
func mockResolver(hosts map[string]*ResolvedHost) sshResolver {
	return func(hostname string) (*ResolvedHost, error) {
		if r, ok := hosts[hostname]; ok {
			return r, nil
		}
		return nil, fmt.Errorf("unknown host: %s", hostname)
	}
}

// mockRemotes returns a fixed set of configured rclone remotes.
func mockRemotes(names ...string) remoteListFunc {
	return func() (map[string]bool, error) {
		m := map[string]bool{}
		for _, n := range names {
			m[n] = true
		}
		return m, nil
	}
}

func TestRewriteArgs_SingleRemote(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{
		"myserver": {
			Host: "10.0.0.1",
			User: "deploy",
			Port: "2222",
		},
	})
	remotes := mockRemotes()

	args := []string{"ls", "myserver:/data"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("len = %d, want 2: %v", len(got), got)
	}
	if got[0] != "ls" {
		t.Errorf("got[0] = %q", got[0])
	}
	// Should contain :sftp,host=10.0.0.1,user=deploy,port=2222,...:/data
	if !strings.HasPrefix(got[1], ":sftp,") {
		t.Errorf("expected :sftp prefix, got %q", got[1])
	}
	if !strings.Contains(got[1], "host=10.0.0.1") {
		t.Errorf("missing host in %q", got[1])
	}
	if !strings.Contains(got[1], "user=deploy") {
		t.Errorf("missing user in %q", got[1])
	}
	if !strings.Contains(got[1], "port=2222") {
		t.Errorf("missing port in %q", got[1])
	}
	if !strings.HasSuffix(got[1], ":/data") {
		t.Errorf("expected :/data suffix, got %q", got[1])
	}
}

func TestRewriteArgs_DualRemote(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{
		"serverA": {Host: "10.0.0.1", User: "root", Port: "22"},
		"serverB": {Host: "10.0.0.2", User: "admin", Port: "22"},
	})
	remotes := mockRemotes()

	args := []string{"copy", "serverA:/src", "serverB:/dst", "--progress"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 4 {
		t.Fatalf("len = %d, want 4: %v", len(got), got)
	}
	if !strings.Contains(got[1], "host=10.0.0.1") {
		t.Errorf("serverA not resolved in %q", got[1])
	}
	if !strings.Contains(got[2], "host=10.0.0.2") {
		t.Errorf("serverB not resolved in %q", got[2])
	}
	if got[3] != "--progress" {
		t.Errorf("flag not preserved: %q", got[3])
	}
}

func TestRewriteArgs_ConfiguredRemotePassthrough(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{})
	remotes := mockRemotes("gdrive:", "s3:")

	args := []string{"ls", "gdrive:/photos"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got[1] != "gdrive:/photos" {
		t.Errorf("configured remote should pass through, got %q", got[1])
	}
}

func TestRewriteArgs_OnTheFlyBackendPassthrough(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{})
	remotes := mockRemotes()

	args := []string{"ls", ":sftp,host=example.com:/data"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got[1] != ":sftp,host=example.com:/data" {
		t.Errorf("on-the-fly backend should pass through, got %q", got[1])
	}
}

func TestRewriteArgs_FlagsPreserved(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{
		"myhost": {Host: "1.2.3.4", User: "root", Port: "22"},
	})
	remotes := mockRemotes()

	args := []string{"--verbose", "sync", "myhost:/src", "/local/dst", "--dry-run", "--progress"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got[0] != "--verbose" {
		t.Errorf("flag not preserved: %q", got[0])
	}
	if got[1] != "sync" {
		t.Errorf("command not preserved: %q", got[1])
	}
	if !strings.Contains(got[2], "host=1.2.3.4") {
		t.Errorf("host not resolved: %q", got[2])
	}
	if got[3] != "/local/dst" {
		t.Errorf("local path not preserved: %q", got[3])
	}
	if got[4] != "--dry-run" {
		t.Errorf("flag not preserved: %q", got[4])
	}
}

func TestRewriteArgs_NoArgs(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{})
	remotes := mockRemotes()

	got, err := rewriteArgsWith([]string{}, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("expected empty, got %v", got)
	}
}

func TestRewriteArgs_PlainCommand(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{})
	remotes := mockRemotes()

	args := []string{"version"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || got[0] != "version" {
		t.Errorf("plain command should pass through: %v", got)
	}
}

func TestRewriteArgs_UnknownHostWarning(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{})
	remotes := mockRemotes()

	// "badhost" is not in the resolver, so it should warn and pass through
	args := []string{"ls", "badhost:/path"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// Should be passed through unchanged
	if got[1] != "badhost:/path" {
		t.Errorf("unknown host should pass through, got %q", got[1])
	}
}

func TestRewriteArgs_WithProxy(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{
		"proxyhost": {
			Host:         "192.168.1.1",
			User:         "root",
			Port:         "22",
			ProxyCommand: "connect-proxy -S socks.example.com:1080 %h %p",
		},
	})
	remotes := mockRemotes()

	args := []string{"ls", "proxyhost:/"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.Contains(got[1], "socks_proxy=\"socks.example.com:1080\"") {
		t.Errorf("proxy not in output: %q", got[1])
	}
}

func TestRewriteArgs_DefaultPortOmitted(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{
		"myhost": {Host: "1.2.3.4", User: "root", Port: "22"},
	})
	remotes := mockRemotes()

	args := []string{"ls", "myhost:/"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if strings.Contains(got[1], "port=") {
		t.Errorf("default port 22 should be omitted, got %q", got[1])
	}
}

func TestRewriteArgs_MixedRemoteAndLocal(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{
		"srv": {Host: "10.0.0.5", User: "user", Port: "22"},
	})
	remotes := mockRemotes()

	// rclone sync srv:/remote /local/path
	args := []string{"sync", "srv:/remote", "/local/path"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 3 {
		t.Fatalf("len = %d, want 3", len(got))
	}
	if !strings.HasPrefix(got[1], ":sftp,") {
		t.Errorf("remote should be rewritten: %q", got[1])
	}
	if got[2] != "/local/path" {
		t.Errorf("local path should be unchanged: %q", got[2])
	}
}

func TestBuildSFTPBackend_WithKeyFile(t *testing.T) {
	// Create a temp file to simulate an existing key
	tmpFile, err := os.CreateTemp("", "test_key_*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(tmpFile.Name())
	tmpFile.Close()

	r := &ResolvedHost{
		Host:          "10.0.0.1",
		User:          "deploy",
		Port:          "2222",
		IdentityFiles: []string{tmpFile.Name()},
	}
	result, err := buildSFTPBackend(r, "/data", "myhost")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.Contains(result, "key_file="+tmpFile.Name()) {
		t.Errorf("key_file not in output: %q", result)
	}
}

func TestBuildSFTPBackend_NonexistentKeySkipped(t *testing.T) {
	r := &ResolvedHost{
		Host:          "10.0.0.1",
		User:          "root",
		Port:          "22",
		IdentityFiles: []string{"/nonexistent/key/path"},
	}
	result, err := buildSFTPBackend(r, "/", "host")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if strings.Contains(result, "key_file=") {
		t.Errorf("nonexistent key should be skipped, got %q", result)
	}
}

func TestBuildSFTPBackend_HTTPProxy(t *testing.T) {
	r := &ResolvedHost{
		Host:         "10.0.0.1",
		User:         "root",
		Port:         "22",
		ProxyCommand: "connect-proxy -H http-proxy.lan:8080 %h %p",
	}
	result, err := buildSFTPBackend(r, "/", "host")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.Contains(result, "http_proxy=\"http://http-proxy.lan:8080\"") {
		t.Errorf("HTTP proxy not in output: %q", result)
	}
}

func TestRewriteArgs_WindowsDriveLetterPassthrough(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{})
	remotes := mockRemotes()

	args := []string{"ls", "C:\\Users\\test"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// This doesn't even have a colon pattern (backslash path), passes through
	if got[1] != "C:\\Users\\test" {
		t.Errorf("should pass through: %q", got[1])
	}
}

func TestRewriteArgs_EmptyPathAfterColon(t *testing.T) {
	resolve := mockResolver(map[string]*ResolvedHost{
		"myhost": {Host: "1.2.3.4", User: "root", Port: "22"},
	})
	remotes := mockRemotes()

	// rclone ls myhost:  (empty path = root)
	args := []string{"ls", "myhost:"}
	got, err := rewriteArgsWith(args, resolve, remotes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasPrefix(got[1], ":sftp,") {
		t.Errorf("should be rewritten: %q", got[1])
	}
	if !strings.HasSuffix(got[1], ":") {
		t.Errorf("should end with empty path colon: %q", got[1])
	}
}

func TestRewriteArgs_MultipleCommandTypes(t *testing.T) {
	// Test that various rclone commands with two remotes all work
	resolve := mockResolver(map[string]*ResolvedHost{
		"src": {Host: "10.0.0.1", User: "root", Port: "22"},
		"dst": {Host: "10.0.0.2", User: "root", Port: "22"},
	})
	remotes := mockRemotes()

	commands := []string{"copy", "sync", "move", "check", "bisync"}
	for _, cmd := range commands {
		args := []string{cmd, "src:/a", "dst:/b"}
		got, err := rewriteArgsWith(args, resolve, remotes)
		if err != nil {
			t.Fatalf("%s: unexpected error: %v", cmd, err)
		}
		if len(got) != 3 {
			t.Fatalf("%s: len = %d, want 3", cmd, len(got))
		}
		if !strings.Contains(got[1], "host=10.0.0.1") {
			t.Errorf("%s: src not resolved", cmd)
		}
		if !strings.Contains(got[2], "host=10.0.0.2") {
			t.Errorf("%s: dst not resolved", cmd)
		}
	}
}
