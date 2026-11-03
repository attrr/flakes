autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats '%b%m '
zstyle ':vcs_info:*' check-for-changes false
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' actionformats '%b|%a%m '
zstyle ':vcs_info:git*+set-message:*' hooks git-status
+vi-git-status() {
	# colors
	local PROMPT_VCS_COLOR_MODIFIED=178
	local PROMPT_VCS_COLOR_UNTRACKED=39
	local PROMPT_VCS_COLOR_CONFLICTED=196

	local git_status
	git_status="$(${vcs_comm[cmd]} status --porcelain=v2 --branch 2>/dev/null)"
	[[ -z "$git_status" ]] && return

	local -a lines
	lines=("${(@f)git_status}")

	local ahead=0 behind=0
	local staged=0 unstaged=0 untracked=0 conflicted=0
	
	for line in "$lines[@]"; do
		case "$line" in
			\#\ branch.ab\ *)
				local parts=("${(@s: :)line}")
				ahead=${parts[3]#+}
				behind=${parts[4]#-}
				;;
			\#\ branch.head\ *)
				# vcs_info already gives us the branch
				;;
			\?\ *)
				((untracked++))
				;;
			u\ *)
				((conflicted++))
				;;
			1\ *|2\ *)
				local xy="${line:2:2}"
				local x="${xy:0:1}"
				local y="${xy:1:1}"
				[[ "$x" != "." ]] && ((staged++))
				[[ "$y" != "." ]] && ((unstaged++))
				;;
		esac
	done

	# Stash check
	local stash_count
	stash_count=$(git rev-list --walk-reflogs --count refs/stash 2>/dev/null)

	# Build format using arrays
	local -a branch_parts
	local -a misc_parts

	local branch_status=""
	(( behind > 0 )) && branch_status+="⇣${behind}"
	(( ahead > 0 )) && branch_status+="⇡${ahead}"
	
	[[ -n "$branch_status" ]] && branch_parts+=("$branch_status")
	[[ -n "$stash_count" && "$stash_count" -gt 0 ]] && branch_parts+=("*${stash_count}")
	(( conflicted > 0 )) && branch_parts+=("%F{$PROMPT_VCS_COLOR_CONFLICTED}~$conflicted%f")

	(( ${#branch_parts} > 0 )) && hook_com[branch]+=" ${(j: :)branch_parts}"
	
	(( staged > 0 )) && misc_parts+=("%F{$PROMPT_VCS_COLOR_MODIFIED}+${staged}%f")
	(( unstaged > 0 )) && misc_parts+=("%F{$PROMPT_VCS_COLOR_MODIFIED}!${unstaged}%f")
	(( untracked > 0 )) && misc_parts+=("%F{$PROMPT_VCS_COLOR_UNTRACKED}?${untracked}%f")

	if (( ${#misc_parts} > 0 )); then
		hook_com[misc]=" ${(j: :)misc_parts}"
	else
		hook_com[misc]=""
	fi
}

function vcs-info-background() {
	if zle -l vcs-info-update; then
		local vcs_info_fd
		exec {vcs_info_fd}< <(
			vcs_info
			print $vcs_info_msg_0_
		)
		zle -F -w $vcs_info_fd vcs-info-update
	fi
}

function vcs-info-update() {
	local vcs_info_pre=$vcs_info_msg_0_
	IFS='' read -ru$1 vcs_info_msg_0_
	if [[ $vcs_info_msg_0_ != $vcs_info_pre ]]; then
		zle reset-prompt
	fi
	zle -F $1
	exec {1} <&-
}
zle -N vcs-info-update

function vcs-info-clear () {
    if zle -l vcs-info-update; then
		vcs_info_msg_0_=""
    fi
}
