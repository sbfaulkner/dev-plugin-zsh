# dev command wrapper
function dev {
  _dev_update
  _dev "$@"
}

# actual entry-point (to enable update)
function _dev {
  _dev_reload

  (( $# > 0 )) || {
    _dev::help
    return 1
  }

  local command="$1"
  shift

  (( $+_dev_commands[$command] )) && {
    sh -c "$_dev_commands[$command]" "$@"
    return $?
  }

  (( $+functions[_dev::$command] )) || {
    _dev::help
    return 1
  }

  _dev::$command "$@"
}

#
# sub-commands
#

# usage
function _dev::help {
  local commands=${(pj:, :)${(ok)_dev_commands}}

  cat >&2 <<EOF
Usage: dev <command> [options]

Available commands:

  help                Print this help message
  clone <repo>        Clone a repo from GitHub
  open <target>       Open a target URL in your browser

Project-specific commands:

  $commands
EOF
}

# clone a repo from github
function _dev::clone {
  (( $# > 0 )) || {
    echo >&2 "Usage: dev clone <repo>"
    return 1
  }

  local login=$(_dev_gh_auth)
  local repo=$(basename $1)
  local owner=${${$(dirname $1):#.}:-$login}
  local dir="$HOME/src/github.com/$owner/$repo"

  if [[ -d $dir ]]; then
    echo "$dir already exists."
  else
    gh repo clone $owner/$repo $dir || return $?
  fi

  cd $dir
}

# open a url
function _dev::open {
  (( $# > 0 )) || {
    cat >&2 <<EOF
Usage: dev open <target>

Targets:
  gh    Open the repo on GitHub
  pr    Open a PR on GitHub
EOF
    return 1
  }

  local target="$1"
  shift

  case "$target" in
    gh)
      gh repo view --web
      ;;
    pr)
      gh pr create --web
      ;;
    *)
      echo >&2 "Unable to open unknown target: $target"
      return 1
      ;;
  esac
}

#
# zsh hooks
#

autoload -U add-zsh-hook
add-zsh-hook chpwd _dev_chpwd
function _dev_chpwd() {
  _dev_reload
}

#
# helper/utility functions
#

# github cli authentication
function _dev_gh_auth {
  gh auth status >/dev/null 2>&1 || {
    local token

    echo "A personal API token is required to access GitHub. You can get one by visiting"
    echo "https://github.com/settings/tokens/new?scopes=repo,read:org&description=dev.plugin"

    echo -n "Please enter your token: "
    read token
    echo $token | gh auth login --hostname github.com --with-token
  }

  gh api user | ruby -rjson -e 'puts JSON.load($stdin)["login"]'
}

# load current dev.yml
function _dev_load {
  _dev_root=$(_dev_path) && {
    echo "💻 ${_dev_root/$HOME/~}/dev.yml"
    eval $(_dev_loader)
  }
  _dev_loaded_at=$(_dev_yml_mtime)
}

function _dev_loader {
  ruby -ryaml -rshellwords - $_dev_root/dev.yml <<'LOADER'
puts "typeset -Ag _dev_commands=("
Hash(YAML.load_file(ARGV.first)["commands"]).each do |name, script|
  script = script["run"] if script.is_a?(Hash)
  script = %(#{script} "$@") if script.lines.size == 1 && !script.include?('$@') && !script.include?('$*')

  puts %(  [#{name}]=#{Shellwords.escape(script)})
end
puts ")"
LOADER
}

# determine mtime of source for dev command
function _dev_mtime {
  date -r $functions_source[dev] +%s
}

# determine path of parent directory containing dev.yml
function _dev_path {
  local dir=$(pwd)
  while [[ $dir != / ]]; do
    [[ -f $dir/dev.yml ]] && {
      echo $dir
      return 0
    }
    dir=$(dirname $dir)
  done
  return 1
}

# reload dev.yml if changed
function _dev_reload {
  [[ $(_dev_path) == $_dev_root && $(_dev_yml_mtime) -eq $_dev_loaded_at ]] || {
    _dev_load
  }
}

# reload dev if changed
function _dev_update {
  [[ $(_dev_mtime) -eq $_dev_modified_at ]] || {
    source $functions_source[dev]
  }
}

# determine mtime of current dev.yml
function _dev_yml_mtime {
  date -r $_dev_root/dev.yml +%s 2>/dev/null
}

_dev_modified_at=$(_dev_mtime)
_dev_load
