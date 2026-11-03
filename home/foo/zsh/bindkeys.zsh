# create a zkbd compatible hash;
# to add other keys to this hash, see: man 5 terminfo
typeset -g -A key
key=(
    Home        "${terminfo[khome]}"
    End         "${terminfo[kend]}"
    Insert      "${terminfo[kich1]}"
    Backspace   "${terminfo[kbs]}"
    Delete      "${terminfo[kdch1]}"
    Up          "${terminfo[kcuu1]}"
    Down        "${terminfo[kcud1]}"
    Left        "${terminfo[kcub1]}"
    Right       "${terminfo[kcuf1]}"
    PageUp      "${terminfo[kpp]}"
    PageDown    "${terminfo[knp]}"
    Shift-Tab   "${terminfo[kcbt]}"
)

# setup key accordingly
bindkey -- "${key[Home]}"       beginning-of-line
bindkey -- "${key[End]}"        end-of-line
bindkey -- "${key[Insert]}"     overwrite-mode
bindkey -- "${key[Backspace]}"  backward-delete-char
bindkey -- "${key[Delete]}"     delete-char
bindkey -- "${key[Up]}"         up-line-or-history
bindkey -- "${key[Down]}"       down-line-or-history
bindkey -- "${key[Left]}"       backward-char
bindkey -- "${key[Right]}"      forward-char
bindkey -- "${key[PageUp]}"     history-beginning-search-backward
bindkey -- "${key[PageDown]}"   history-beginning-search-forward
bindkey -- "${key[Shift-Tab]}"  reverse-menu-complete

# Make sure the terminal is in application mode, when zle is
# active. Only then are the values from $terminfo valid.
function zle-line-init () {
    echoti smkx
}
function zle-line-finish () {
    echoti rmkx
}
zle -N zle-line-init
zle -N zle-line-finish
