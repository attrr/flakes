function sudo-command-line() {
    local editors=(vi vim nvim emacs nano)
    local prefix=${${(zA)BUFFER}[1]}

    if [[ $prefix == sudo ]]; then
        LBUFFER="${LBUFFER#sudo }"
    elif [[ $prefix == sudoedit ]]; then
        LBUFFER="${LBUFFER#sudoedit }"
        LBUFFER="$EDITOR $LBUFFER"
    elif (( $editors[(Ie)$prefix] )); then
        LBUFFER="${LBUFFER#$prefix }"
        LBUFFER="sudoedit $LBUFFER"
    else
        LBUFFER="sudo $LBUFFER"
    fi

    # refresh highlight
    _zsh_highlight
}
zle -N sudo-command-line
bindkey -M emacs '\e\e' sudo-command-line
