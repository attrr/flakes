function last-exit-status() {
	local last_exit=$?

	local PROMPT_INDICATOR_COLOR_SUCCESS=076
	local PROMPT_INDICATOR_COLOR_ERROR=160

	if [[ $last_exit -ne 0 ]]; then
		PROMPT_INDICATOR=%F{$PROMPT_INDICATOR_COLOR_ERROR}❯%f
	else
		PROMPT_INDICATOR=%F{$PROMPT_INDICATOR_COLOR_SUCCESS}❯%f
	fi
}

zmodload zsh/datetime
function pre-execution-time() {
	typeset -g PROMPT_EXEC_PRE_TIME=${EPOCHREALTIME}
}
function last-execution-time() {
	local PROMPT_TIME_COLOR=101
	if [[ -n "$PROMPT_EXEC_PRE_TIME" ]]; then
		local elapsed=$(((EPOCHREALTIME - PROMPT_EXEC_PRE_TIME) * 1000))
		elapsed=${elapsed%.*}
		export PROMPT_EXEC_TIME="%F{$PROMPT_TIME_COLOR}took ${elapsed}ms%{$reset_color%}"
		unset PROMPT_EXEC_PRE_TIME
	else
		export PROMPT_EXEC_TIME=""
	fi
}

function current-netns() {
	local PROMPT_NETNS_COLOR=7
	local netns=$(ip netns identify $$ 2>/dev/null)
	if [[ -n $netns ]]; then
		PROMPT_NETNS="%F{$PROMPT_NETNS_COLOR}(🖧 ${netns})%f "
	else
		PROMPT_NETNS=""
	fi
}

function current-direnv() {
	local PROMPT_DIRENV_COLOR=178
	if [[ -n $DIRENV_DIR ]]; then
		PROMPT_DIRENV=" %F{$PROMPT_DIRENV_COLOR}▼%f"
	else
		PROMPT_DIRENV=""
	fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd last-exit-status
add-zsh-hook preexec pre-execution-time
add-zsh-hook precmd last-execution-time
add-zsh-hook precmd current-netns
add-zsh-hook precmd current-direnv
# git
source "${${0}%/*}/git.zsh"
add-zsh-hook precmd vcs-info-background
add-zsh-hook chpwd vcs-info-clear

PROMPT_CWD_COLOR=39
PROMPT_DEFAULT_COLOR=076

setopt prompt_subst
PROMPT='${PROMPT_NETNS}'                                # netns
PROMPT+="%B%F{$PROMPT_CWD_COLOR}%~%b "                  # cwd
PROMPT+="%F{$PROMPT_DEFAULT_COLOR}"'${vcs_info_msg_0_}' # git
PROMPT+='${PROMPT_INDICATOR} '                          # indicator
RPROMPT='${PROMPT_EXEC_TIME}${PROMPT_DIRENV}'

unset PROMPT_CWD_COLOR PROMPT_DEFAULT_COLOR
