package main

import (
	"testing"
)

func TestParseProxyCommand_ConnectProxySOCKS5(t *testing.T) {
	p := ParseProxyCommand("connect-proxy -S proxy.example.com:1080 %h %p")
	if p == nil {
		t.Fatal("expected proxy, got nil")
	}
	if p.Type != "socks5" {
		t.Errorf("Type = %v, want SOCKS5", p.Type)
	}
	if p.Address != "proxy.example.com:1080" {
		t.Errorf("Address = %q", p.Address)
	}
}

func TestParseProxyCommand_ConnectProxyHTTP(t *testing.T) {
	p := ParseProxyCommand("connect-proxy -H http-proxy.example.com:8080 %h %p")
	if p == nil {
		t.Fatal("expected proxy, got nil")
	}
	if p.Type != "http" {
		t.Errorf("Type = %v, want HTTP", p.Type)
	}
	if p.Address != "http-proxy.example.com:8080" {
		t.Errorf("Address = %q", p.Address)
	}
}

func TestParseProxyCommand_NcSOCKS5(t *testing.T) {
	p := ParseProxyCommand("nc -X 5 -x socks.lan:1080 %h %p")
	if p == nil {
		t.Fatal("expected proxy, got nil")
	}
	if p.Type != "socks5" {
		t.Errorf("Type = %v, want SOCKS5", p.Type)
	}
	if p.Address != "socks.lan:1080" {
		t.Errorf("Address = %q", p.Address)
	}
}

func TestParseProxyCommand_NcHTTP(t *testing.T) {
	p := ParseProxyCommand("nc -X connect -x http.proxy:3128 %h %p")
	if p == nil {
		t.Fatal("expected proxy, got nil")
	}
	if p.Type != "http" {
		t.Errorf("Type = %v, want HTTP", p.Type)
	}
	if p.Address != "http.proxy:3128" {
		t.Errorf("Address = %q", p.Address)
	}
}

func TestParseProxyCommand_FullPathBinary(t *testing.T) {
	p := ParseProxyCommand("/usr/bin/nc -X 5 -x proxy:1080 %h %p")
	if p == nil {
		t.Fatal("expected proxy, got nil")
	}
	if p.Type != "socks5" {
		t.Errorf("Type = %v, want SOCKS5", p.Type)
	}
}

func TestParseProxyCommand_Ncat(t *testing.T) {
	p := ParseProxyCommand("ncat -X 5 -x proxy:1080 %h %p")
	if p == nil {
		t.Fatal("expected proxy, got nil")
	}
	if p.Type != "socks5" {
		t.Errorf("Type = %v, want SOCKS5", p.Type)
	}
}

func TestParseProxyCommand_Unsupported(t *testing.T) {
	tests := []string{
		"ssh -W %h:%p jumphost",        // ProxyJump-style
		"/bin/bash -c 'connect %h %p'", // custom script
		"socat - TCP:%h:%p",            // socat
		"",                             // empty
	}
	for _, cmd := range tests {
		p := ParseProxyCommand(cmd)
		if p != nil {
			t.Errorf("ParseProxyCommand(%q) = %+v, want nil", cmd, p)
		}
	}
}

func TestParseProxyCommand_NcMissingAddr(t *testing.T) {
	// Has -X but no -x
	p := ParseProxyCommand("nc -X 5 %h %p")
	if p != nil {
		t.Errorf("expected nil for nc without -x, got %+v", p)
	}
}

func TestProxyInfo_RcloneProxyFlag_SOCKS5(t *testing.T) {
	p := &ProxyInfo{Type: "socks5", Address: "proxy:1080"}
	name, val := p.RcloneProxyFlag()
	if name != "socks_proxy" {
		t.Errorf("name = %q, want %q", name, "socks_proxy")
	}
	if val != "proxy:1080" {
		t.Errorf("val = %q", val)
	}
}

func TestProxyInfo_RcloneProxyFlag_HTTP(t *testing.T) {
	p := &ProxyInfo{Type: "http", Address: "proxy:8080"}
	name, val := p.RcloneProxyFlag()
	if name != "http_proxy" {
		t.Errorf("name = %q, want %q", name, "http_proxy")
	}
	if val != "http://proxy:8080" {
		t.Errorf("val = %q", val)
	}
}
