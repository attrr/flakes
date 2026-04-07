package main

import (
	"fmt"
	"strings"
)

// ProxyInfo holds a parsed proxy address and its type ("socks5" or "http").
type ProxyInfo struct {
	Type    string // "socks5" or "http"
	Address string // host:port
}

// ParseProxyCommand extracts proxy information from an SSH ProxyCommand.
//
// Supported patterns:
//
//	connect-proxy -S host:port %h %p   → SOCKS5
//	connect-proxy -H host:port %h %p   → HTTP
//	nc -X 5 -x host:port %h %p         → SOCKS5
//	nc -X connect -x host:port %h %p   → HTTP
//
// Returns nil for unrecognised commands (not an error).
func ParseProxyCommand(cmd string) *ProxyInfo {
	cmd = strings.TrimSpace(cmd)
	if cmd == "" {
		return nil
	}
	fields := strings.Fields(cmd)
	if len(fields) == 0 {
		return nil
	}

	// Strip directory prefix: /usr/bin/nc → nc
	bin := fields[0]
	if i := strings.LastIndex(bin, "/"); i >= 0 {
		bin = bin[i+1:]
	}

	switch bin {
	case "connect-proxy":
		return parseConnectProxy(fields[1:])
	case "nc", "ncat", "netcat":
		return parseNc(fields[1:])
	}
	return nil
}

// parseConnectProxy: -S host:port → SOCKS5, -H host:port → HTTP.
func parseConnectProxy(args []string) *ProxyInfo {
	for i := 0; i+1 < len(args); i++ {
		switch args[i] {
		case "-S":
			return &ProxyInfo{Type: "socks5", Address: args[i+1]}
		case "-H":
			return &ProxyInfo{Type: "http", Address: args[i+1]}
		}
	}
	return nil
}

// parseNc: -X 5 → SOCKS5, -X connect → HTTP; -x supplies the address.
func parseNc(args []string) *ProxyInfo {
	var proxyType string
	var addr string

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "-X":
			if i+1 < len(args) {
				i++
				switch args[i] {
				case "5":
					proxyType = "socks5"
				case "connect":
					proxyType = "http"
				}
			}
		case "-x":
			if i+1 < len(args) {
				i++
				addr = args[i]
			}
		}
	}

	if proxyType != "" && addr != "" {
		return &ProxyInfo{Type: proxyType, Address: addr}
	}
	return nil
}

// RcloneProxyFlag returns the rclone SFTP backend parameter name and value.
//   - socks5 → socks_proxy, bare host:port
//   - http   → http_proxy, full http://host:port URL
func (p *ProxyInfo) RcloneProxyFlag() (paramName string, paramValue string) {
	switch p.Type {
	case "socks5":
		return "socks_proxy", p.Address
	case "http":
		return "http_proxy", fmt.Sprintf("http://%s", p.Address)
	}
	return "", ""
}
