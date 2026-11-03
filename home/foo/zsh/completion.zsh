zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME}/zsh/zcompcache"
zstyle ':completion:*' menu select
zstyle ":completion:*:default" list-colors "${(s.:.)LS_COLORS}"
# show all process of user
zstyle ':completion:*:processes' command 'ps -u $USER -o pid,user,comm -w -w'
# grouping and color
zstyle ':completion:*' group-name ''
zstyle ':completion:*:parameters'  list-colors '=*=32'
zstyle ':completion:*:commands' list-colors '=*=1;31'
zstyle ':completion:*:builtins' list-colors '=*=1;38;5;142'
zstyle ':completion:*:aliases' list-colors '=*=2;38;5;128'
# alias/reimplement
compdef _rclone rclone-ssh
_kdig() {
	_dig "$@"
	args+=(
		'*+'{no,}'tls[use TLS with the Opportunistic privacy profile]'
	)
}
compdef _kdig kdig
# bash completion
autoload -U +X bashcompinit; bashcompinit
load-bash-comp() {
	local prefix=/usr/share/bash-completion/completions
	for name in $@; do
		local file="${prefix}/${name}"
		if [[ -f "${file}" ]]; then
			source $file
		fi
	done
}
load-bash-comp \
	guestfish \
	virt-install \
	virt-customize \
	virt-builder
