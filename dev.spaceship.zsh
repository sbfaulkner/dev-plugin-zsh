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

  # TODO: detect if `dev up` is needed
  local 'dev_status'

  dev_status=${_dev_name}
  # if [[ $SOME_CONDITION ]]; then
  #   dev_status=$(dev baz)
  # else
  #   dev_status=$(dev foo)
  # fi

  # Exit section if variable is empty
  [[ -z $dev_status ]] && return

  # Display dev section
  spaceship::section \
    "$SPACESHIP_DEV_COLOR" \
    "$SPACESHIP_DEV_PREFIX" \
    "$SPACESHIP_DEV_SYMBOL$dev_status" \
    "$SPACESHIP_DEV_SUFFIX"
}
