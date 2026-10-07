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
