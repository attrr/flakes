package main

import (
	"fmt"
	"os"
	"strings"
	"testing"
)

// --- Context Detection and Helper Tests ---

func TestLastArg(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want string
	}{
		{"empty", nil, ""},
		{"single", []string{"foo"}, "foo"},
		{"multi", []string{"a", "b", "c"}, "c"},
		{"empty string", []string{"a", ""}, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := lastArg(tt.args); got != tt.want {
				t.Errorf("lastArg(%v) = %q, want %q", tt.args, got, tt.want)
			}
		})
	}
}

func TestIsHostPath(t *testing.T) {
	tests := []struct {
		word string
		want bool
	}{
		{"myhost:/path", true},
		{"myhost:", true},
		{"host:relative", true},
		{"ab:", true},
		{"--flag", false},
		{"-v", false},
		{":sftp,host=x:", false},
		{"C:", true},
		{"copy", false},
		{"", false},
		{"/local/path", false},
	}
	for _, tt := range tests {
		t.Run(tt.word, func(t *testing.T) {
			if got := isHostPath(tt.word); got != tt.want {
				t.Errorf("isHostPath(%q) = %v, want %v", tt.word, got, tt.want)
			}
		})
	}
}

func TestIsRemotePosition(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want bool
	}{
		{"after subcommand", []string{"copy", ""}, true},
		{"after subcommand bare", []string{"sync", "some"}, true},
		{"subcommand only", []string{"copy"}, false},
		{"empty", nil, false},
		{"flag last", []string{"copy", "--dry-run"}, false},
		{"flag dash", []string{"copy", "-v"}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := isRemotePosition(tt.args); got != tt.want {
				t.Errorf("isRemotePosition(%v) = %v, want %v", tt.args, got, tt.want)
			}
		})
	}
}

func TestSplitHostPath(t *testing.T) {
	tests := []struct {
		word     string
		wantHost string
		wantPath string
	}{
		{"myhost:/usr/local", "myhost", "/usr/local"},
		{"myhost:", "myhost", ""},
		{"nocolon", "nocolon", ""},
	}
	for _, tt := range tests {
		t.Run(tt.word, func(t *testing.T) {
			h, p := splitHostPath(tt.word)
			if h != tt.wantHost || p != tt.wantPath {
				t.Errorf("splitHostPath(%q) = (%q, %q), want (%q, %q)",
					tt.word, h, p, tt.wantHost, tt.wantPath)
			}
		})
	}
}

// --- SSH Configuration Parsing Tests ---

func TestParseSSHConfigHosts(t *testing.T) {
	config := `# A comment
Host server1 server2
    HostName 10.0.0.1
    User deploy

Host *.example.com
    User wildcard

Host !negated
    User nobody

Host server3
    HostName 10.0.0.3

# Duplicate of server1
Host server1
    Port 2222

Host jump-host bastion
    HostName 192.168.1.1
`
	hosts := parseSSHConfigHosts(config)

	want := []string{"bastion", "jump-host", "server1", "server2", "server3"}
	if len(hosts) != len(want) {
		t.Fatalf("got %v, want %v", hosts, want)
	}
	for i, h := range hosts {
		if h != want[i] {
			t.Errorf("hosts[%d] = %q, want %q", i, h, want[i])
		}
	}
}

func TestParseSSHConfigHosts_Empty(t *testing.T) {
	hosts := parseSSHConfigHosts("")
	if len(hosts) != 0 {
		t.Errorf("expected empty, got %v", hosts)
	}
}

func TestParseSSHConfigHosts_OnlyWildcards(t *testing.T) {
	config := `Host *
    User default

Host *.internal
    ProxyJump bastion
`
	hosts := parseSSHConfigHosts(config)
	if len(hosts) != 0 {
		t.Errorf("expected empty (all wildcards), got %v", hosts)
	}
}

func TestParseSSHConfigHosts_EqualsSign(t *testing.T) {
	config := `Host=equalhost
    HostName 10.0.0.1
`
	hosts := parseSSHConfigHosts(config)
	if len(hosts) != 1 || hosts[0] != "equalhost" {
		t.Errorf("got %v, want [equalhost]", hosts)
	}
}

func TestParseSSHConfigHosts_TabSeparated(t *testing.T) {
	config := "Host\ttabhost\n\tHostName 10.0.0.1\n"
	hosts := parseSSHConfigHosts(config)
	if len(hosts) != 1 || hosts[0] != "tabhost" {
		t.Errorf("got %v, want [tabhost]", hosts)
	}
}

func TestGetSSHConfigHosts_ReaderError(t *testing.T) {
	failReader := func() (string, error) {
		return "", fmt.Errorf("no config")
	}
	hosts := getSSHConfigHosts(failReader)
	if hosts != nil {
		t.Errorf("expected nil on error, got %v", hosts)
	}
}

// --- Standard Output Capture Utility ---

// captureStdout suppresses os.Stdout and returns all written output.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()

	oldStdout := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	os.Stdout = w

	fn()

	w.Close()
	os.Stdout = oldStdout

	buf := make([]byte, 64*1024)
	n, _ := r.Read(buf)
	r.Close()
	return string(buf[:n])
}

// --- Completion Branch Logic Tests ---

func TestCompleteRemoteFiles(t *testing.T) {
	mockRun := func(name string, args ...string) (string, error) {
		if name != "ssh" {
			t.Fatalf("expected ssh, got %q", name)
		}
		if args[0] != "myhost" {
			t.Errorf("host = %q, want myhost", args[0])
		}
		if args[1] != "command" || args[2] != "ls" {
			t.Errorf("unexpected command args: %v", args)
		}
		return "/usr/local/\n/usr/local/bin/\n/usr/local/lib/\n", nil
	}

	output := captureStdout(t, func() {
		completeRemoteFiles("myhost:/usr/lo", mockRun)
	})

	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) != 4 {
		t.Fatalf("expected 4 lines, got %d: %v", len(lines), lines)
	}
	if lines[0] != "myhost:/usr/local/" {
		t.Errorf("line[0] = %q", lines[0])
	}
	if lines[1] != "myhost:/usr/local/bin/" {
		t.Errorf("line[1] = %q", lines[1])
	}
	if lines[2] != "myhost:/usr/local/lib/" {
		t.Errorf("line[2] = %q", lines[2])
	}
	if lines[3] != ":2" {
		t.Errorf("directive = %q, want :2", lines[3])
	}
}

func TestCompleteRemoteFiles_EmptyPath(t *testing.T) {
	mockRun := func(name string, args ...string) (string, error) {
		glob := args[len(args)-1]
		if glob != "*" {
			t.Errorf("expected glob *, got %q", glob)
		}
		return "bin/\netc/\nhome/\n", nil
	}

	output := captureStdout(t, func() {
		completeRemoteFiles("myhost:", mockRun)
	})

	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) != 4 {
		t.Fatalf("expected 4 lines, got %d: %v", len(lines), lines)
	}
	if lines[0] != "myhost:bin/" {
		t.Errorf("line[0] = %q", lines[0])
	}
}

func TestCompleteRemoteFiles_SSHError(t *testing.T) {
	mockRun := func(name string, args ...string) (string, error) {
		return "", fmt.Errorf("connection refused")
	}

	output := captureStdout(t, func() {
		completeRemoteFiles("badhost:/path", mockRun)
	})

	if strings.TrimSpace(output) != ":1" {
		t.Errorf("expected :1 directive on error, got %q", output)
	}
}

func TestCompleteHosts(t *testing.T) {
	mockRun := func(name string, args ...string) (string, error) {
		if name == "rclone" && len(args) > 0 && args[0] == "listremotes" {
			return "gdrive:\ns3:\n", nil
		}
		return "", fmt.Errorf("unexpected command: %s %v", name, args)
	}

	mockConfig := func() (string, error) {
		return `Host server1
    HostName 10.0.0.1

Host server2
    HostName 10.0.0.2

Host *.wildcard
    User nobody
`, nil
	}

	output := captureStdout(t, func() {
		completeHosts(mockRun, mockConfig)
	})

	lines := strings.Split(strings.TrimSpace(output), "\n")

	if len(lines) != 5 {
		t.Fatalf("expected 5 lines, got %d: %v", len(lines), lines)
	}
	if !strings.HasPrefix(lines[0], "server1:") {
		t.Errorf("line[0] = %q", lines[0])
	}
	if !strings.HasPrefix(lines[1], "server2:") {
		t.Errorf("line[1] = %q", lines[1])
	}
	if !strings.HasPrefix(lines[2], "gdrive:") {
		t.Errorf("line[2] = %q", lines[2])
	}
	if !strings.HasPrefix(lines[3], "s3:") {
		t.Errorf("line[3] = %q", lines[3])
	}
	if lines[4] != ":2" {
		t.Errorf("directive = %q, want :2", lines[4])
	}
}

func TestCompleteHosts_NoRclone(t *testing.T) {
	mockRun := func(name string, args ...string) (string, error) {
		return "", fmt.Errorf("rclone not found")
	}

	mockConfig := func() (string, error) {
		return "Host myhost\n    HostName 10.0.0.1\n", nil
	}

	output := captureStdout(t, func() {
		completeHosts(mockRun, mockConfig)
	})

	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 lines, got %d: %v", len(lines), lines)
	}
	if !strings.HasPrefix(lines[0], "myhost:") {
		t.Errorf("line[0] = %q", lines[0])
	}
	if lines[1] != ":2" {
		t.Errorf("directive = %q, want :2", lines[1])
	}
}

// --- Dispatcher Tests ---

func TestHandleComplete_BranchA_HostPath(t *testing.T) {
	mockRun := func(name string, args ...string) (string, error) {
		if name == "ssh" {
			return "file1\nfile2\n", nil
		}
		return "", fmt.Errorf("unexpected")
	}
	mockConfig := func() (string, error) { return "", nil }

	output := captureStdout(t, func() {
		ret := handleCompleteWith([]string{"copy", "myhost:/data/"}, mockRun, mockConfig)
		if ret != 0 {
			t.Errorf("expected exit 0, got %d", ret)
		}
	})

	if !strings.Contains(output, "myhost:file1") {
		t.Errorf("expected host-prefixed files, got %q", output)
	}
}

func TestHandleComplete_BranchB_HostPosition(t *testing.T) {
	mockRun := func(name string, args ...string) (string, error) {
		if name == "rclone" {
			return "mys3:\n", nil
		}
		return "", fmt.Errorf("unexpected")
	}
	mockConfig := func() (string, error) {
		return "Host testhost\n    HostName 10.0.0.1\n", nil
	}

	output := captureStdout(t, func() {
		ret := handleCompleteWith([]string{"copy", ""}, mockRun, mockConfig)
		if ret != 0 {
			t.Errorf("expected exit 0, got %d", ret)
		}
	})

	if !strings.Contains(output, "testhost:") {
		t.Errorf("expected SSH host, got %q", output)
	}
	if !strings.Contains(output, "mys3:") {
		t.Errorf("expected rclone remote, got %q", output)
	}
}

func TestHandleComplete_BranchC_EmptyArgs(t *testing.T) {
	mockRun := func(name string, args ...string) (string, error) {
		return "", fmt.Errorf("should not be called for Branch C")
	}
	mockConfig := func() (string, error) { return "", nil }

	ret := handleCompleteWith([]string{""}, mockRun, mockConfig)
	_ = ret
}

func TestHandleComplete_BranchC_Flags(t *testing.T) {
	mockRun := func(name string, args ...string) (string, error) {
		return "", fmt.Errorf("should not be called")
	}
	mockConfig := func() (string, error) { return "", nil }

	ret := handleCompleteWith([]string{"copy", "--"}, mockRun, mockConfig)
	_ = ret
}
