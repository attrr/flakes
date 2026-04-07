package main

import (
	"strings"
	"testing"
)

func TestParseSSHGOutput_Full(t *testing.T) {
	raw := `hostname 192.168.1.100
user deploy
port 2222
identityfile ~/.ssh/id_ed25519
identityfile ~/.ssh/id_rsa
proxycommand connect-proxy -S proxy.example.com:1080 %h %p
`
	r, err := parseSSHGOutput(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if r.Host != "192.168.1.100" {
		t.Errorf("Host = %q, want %q", r.Host, "192.168.1.100")
	}
	if r.User != "deploy" {
		t.Errorf("User = %q, want %q", r.User, "deploy")
	}
	if r.Port != "2222" {
		t.Errorf("Port = %q, want %q", r.Port, "2222")
	}
	if len(r.IdentityFiles) != 2 {
		t.Fatalf("IdentityFiles len = %d, want 2", len(r.IdentityFiles))
	}
	if r.IdentityFiles[0] != "~/.ssh/id_ed25519" {
		t.Errorf("IdentityFiles[0] = %q, want %q", r.IdentityFiles[0], "~/.ssh/id_ed25519")
	}
	if r.ProxyCommand != "connect-proxy -S proxy.example.com:1080 %h %p" {
		t.Errorf("ProxyCommand = %q", r.ProxyCommand)
	}
}

func TestParseSSHGOutput_Minimal(t *testing.T) {
	raw := `hostname example.com
user root
port 22
proxycommand none
`
	r, err := parseSSHGOutput(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if r.Host != "example.com" {
		t.Errorf("Host = %q", r.Host)
	}
	if r.ProxyCommand != "" {
		t.Errorf("ProxyCommand should be empty for 'none', got %q", r.ProxyCommand)
	}
}

func TestParseSSHGOutput_NoHostname(t *testing.T) {
	raw := `user root
port 22
`
	_, err := parseSSHGOutput(raw)
	if err == nil {
		t.Fatal("expected error for missing hostname")
	}
}

func TestParseSSHGOutput_CaseInsensitive(t *testing.T) {
	// ssh -G output should be lowercase, but test resilience
	raw := `HostName myhost.example.com
User admin
Port 443
IdentityFile /home/test/.ssh/key
`
	r, err := parseSSHGOutput(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if r.Host != "myhost.example.com" {
		t.Errorf("Host = %q", r.Host)
	}
}

func TestResolveSSHWith(t *testing.T) {
	fakeRunner := func(hostname string) (string, error) {
		return `hostname 10.0.0.1
user testuser
port 22
identityfile /home/testuser/.ssh/id_ed25519
proxycommand none
`, nil
	}

	r, err := resolveSSHWith("myhost", fakeRunner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if r.Host != "10.0.0.1" {
		t.Errorf("Host = %q, want %q", r.Host, "10.0.0.1")
	}
	if r.User != "testuser" {
		t.Errorf("User = %q, want %q", r.User, "testuser")
	}
}

func TestParseSSHGOutput_ExtraFields(t *testing.T) {
	// ssh -G outputs many more fields; ensure we skip unknown ones gracefully
	raw := `hostname server.example.com
user admin
port 22
forwardagent no
forwardx11 no
identityfile ~/.ssh/id_rsa
loglevel INFO
compression yes
serveralivecountmax 3
serveraliveinterval 60
proxycommand none
`
	r, err := parseSSHGOutput(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if r.Host != "server.example.com" {
		t.Errorf("Host = %q", r.Host)
	}
	if r.User != "admin" {
		t.Errorf("User = %q", r.User)
	}
	if len(r.IdentityFiles) != 1 {
		t.Errorf("IdentityFiles len = %d, want 1", len(r.IdentityFiles))
	}
}

func TestParseSSHGOutput_EmptyInput(t *testing.T) {
	_, err := parseSSHGOutput("")
	if err == nil {
		t.Fatal("expected error for empty input")
	}
	if !strings.Contains(err.Error(), "no hostname") {
		t.Errorf("error should mention 'no hostname', got: %v", err)
	}
}
