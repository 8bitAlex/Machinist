[[ -x $HOME/.local/bin/starship ]] && path=($HOME/.local/bin $path)

if (( ! $+commands[starship] )); then
  print -u2 "machinist: Starship not found, installing it…"
  if (( $+commands[brew] )); then
    brew install starship
  elif (( $+commands[curl] )); then
    mkdir -p $HOME/.local/bin
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir $HOME/.local/bin
    path=($HOME/.local/bin $path)
  fi
  rehash
  if (( ! $+commands[starship] )); then
    print -u2 "machinist: couldn't install Starship; install it from https://starship.rs"
    return 1
  fi
fi

export STARSHIP_CONFIG="${${(%):-%x}:A:h:h}/starship/machinist.toml"
eval "$(starship init zsh)"

() {
  local font=MesloLGSNerdFontMono-Regular.ttf
  [[ -f $HOME/Library/Fonts/$font || -f /Library/Fonts/$font || -f $HOME/.local/share/fonts/Meslo/$font ]] && return
  if [[ $OSTYPE == darwin* ]]; then
    (( $+commands[brew] )) || return
    print -u2 "machinist: MesloLGS Nerd Font not found, installing it…"
    brew install --cask font-meslo-lg-nerd-font
  elif (( $+commands[fc-list] && $+commands[curl] && $+commands[tar] )); then
    fc-list : family | grep -q "MesloLGS Nerd Font Mono" && return
    print -u2 "machinist: MesloLGS Nerd Font not found, installing it…"
    mkdir -p $HOME/.local/share/fonts/Meslo
    curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.tar.xz |
      tar -xJ -C $HOME/.local/share/fonts/Meslo && fc-cache -f
  fi
}

export SCLIDE_COLOR="#94e344" SCLIDE_FADE_COLOR="#211e20"

function _machinist_background {
  local saved reply char
  saved=$(stty -g < /dev/tty 2>/dev/null) || return 1
  stty -echo -icanon < /dev/tty
  print -n $'\e]11;?\a' > /dev/tty
  while read -r -s -k 1 -t 0.2 char < /dev/tty; do
    [[ $char == $'\a' || $char == '\' ]] && break
    reply+=$char
  done
  stty $saved < /dev/tty
  [[ $reply =~ 'rgb:([0-9a-fA-F]{2})[0-9a-fA-F]*/([0-9a-fA-F]{2})[0-9a-fA-F]*/([0-9a-fA-F]{2})' ]] || return 1
  REPLY="#${match[1]}${match[2]}${match[3]}"
}

function clear {
  if (( ! $+commands[sclide-clear] )); then
    command clear "$@"
    return
  fi
  local sweep=$SCLIDE_COLOR fade=$SCLIDE_FADE_COLOR
  if _machinist_background; then
    fade=$REPLY
    local red=$(( 16#${REPLY[2,3]} )) green=$(( 16#${REPLY[4,5]} )) blue=$(( 16#${REPLY[6,7]} ))
    (( 2126 * red + 7152 * green + 722 * blue > 1275000 )) && sweep="#3d7a1f"
  fi
  SCLIDE_COLOR=$sweep SCLIDE_FADE_COLOR=$fade sclide-clear
}
