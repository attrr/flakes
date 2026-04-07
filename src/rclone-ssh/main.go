// rclone-ssh wraps rclone with transparent SSH config integration.
//
// Arguments matching host:path are resolved against ~/.ssh/config
// (via ssh -G) and rewritten to rclone's on-the-fly :sftp backend.
// Already-configured rclone remotes are passed through unchanged.
//
// Usage:
//
//	rclone-ssh ls myserver:/data
//	rclone-ssh copy serverA:/src serverB:/dst
//	rclone-ssh sync host:/remote /local --progress
package main

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "__complete" {
		os.Exit(handleComplete(os.Args[2:]))
	}

	rewritten, err := RewriteArgs(os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "rclone-ssh: %v\n", err)
		os.Exit(1)
	}

	rclonePath, err := exec.LookPath("rclone")
	if err != nil {
		fmt.Fprintf(os.Stderr, "rclone-ssh: rclone not found in PATH: %v\n", err)
		os.Exit(1)
	}

	// Replace this process with rclone via exec(2). On success this
	// never returns — rclone inherits the tty, signals, and stdio.
	argv := append([]string{"rclone"}, rewritten...)
	if err := syscall.Exec(rclonePath, argv, os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "rclone-ssh: exec failed: %v\n", err)
		os.Exit(1)
	}
}
