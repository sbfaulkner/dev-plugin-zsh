#
# Spaceship extensin for dev
#

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

SPACESHIP_DEV_SHOW="${SPACESHIP_DEV_SHOW=true}"
SPACESHIP_DEV_PREFIX="${SPACESHIP_DEV_PREFIX="$SPACESHIP_PROMPT_DEFAULT_PREFIX"}"
SPACESHIP_DEV_SUFFIX="${SPACESHIP_DEV_SUFFIX="$SPACESHIP_PROMPT_DEFAULT_SUFFIX"}"
SPACESHIP_DEV_SYMBOL="${SPACESHIP_DEV_SYMBOL="💻 "}"
SPACESHIP_DEV_COLOR="${SPACESHIP_DEV_COLOR="blue"}"
SPACESHIP_DEV_COMMAND_COLOR="${SPACESHIP_DEV_COMMAND_COLOR="white"}"

# ------------------------------------------------------------------------------
# Section
# ------------------------------------------------------------------------------

# Show dev status
spaceship_dev() {
  # If SPACESHIP_DEV_SHOW is false, don't show foobar section
  [[ $SPACESHIP_DEV_SHOW == false ]] && return

  # Check if dev command is available for execution
  spaceship::exists dev || return

  # Show dev section only when a project is detected.
  [[ -n "${_dev_root}" ]] || return

  # Use quotes around unassigned local variables to prevent
  # getting replaced by global aliases
  # http://zsh.sourceforge.net/Doc/Release/Shell-Grammar.html#Aliasing

  local 'dev_status'

  # detect if `dev up` is needed
  if [[ $(_dev_mtime "${_dev_root}/dev.yml") -gt $(_dev_up_time) ]]; then
    dev_status="dev.yml modified (run %F{$SPACESHIP_DEV_COMMAND_COLOR}dev up%F{$SPACESHIP_DEV_COLOR})"
  elif [[ $(_dev_mtime "${_dev_root}/Gemfile") -gt $(_dev_mtime "${_dev_root}/Gemfile.lock") ]]; then
    if (( $_dev_up[(I)bundler] > 0 )); then
      dev_status="Gemfile modified (run %F{$SPACESHIP_DEV_COMMAND_COLOR}dev up%F{$SPACESHIP_DEV_COLOR})"
    else
      dev_status="Gemfile modified (run %F{$SPACESHIP_DEV_COMMAND_COLOR}bundle install%F{$SPACESHIP_DEV_COLOR})"
    fi
  else
    dev_status=""
  fi

  # Exit section if variable is empty
  [[ -z $dev_status ]] && return

  # Display dev section
  spaceship::section \
    "$SPACESHIP_DEV_COLOR" \
    "$SPACESHIP_DEV_PREFIX" \
    "$SPACESHIP_DEV_SYMBOL$dev_status" \
    "$SPACESHIP_DEV_SUFFIX"
}
