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

  (( $+_dev_commands[${command}] )) && {
    _dev_exec "${command}" "$@"
    return
  }

  (( $+functions[_dev::${command}] )) || {
    _dev::help
    return 1
  }

  "_dev::${command}" "$@"
}

#
# sub-commands
#

# usage
function _dev::help {
  cat >&2 <<EOF
Usage: dev <command> [options]

Available commands:

  help                Print this help message
  clone <repo>        Clone a repo from GitHub
  open <target>       Open a target URL in your browser
  up                  Install and start dependencies
EOF

  local commands=${(pj:, :)${(ok)_dev_commands}}
  (( $#commands )) || return 0

  cat >&2 <<EOF

Project-specific commands:

  ${commands}
EOF
}

# clone a repo from github
function _dev::clone {
  (( $# > 0 )) || {
    echo >&2 "Usage: dev clone <repo>"
    return 1
  }

  local login repo owner dir

  login="$(_dev_gh_auth)"
  repo="$(basename "$1")"
  owner="${${$(dirname "$1"):#.}:-${login}}"
  dir="${HOME}/src/github.com/${owner}/${repo}"

  if [[ -d "${dir}" ]]; then
    echo "${dir} already exists."
  else
    gh repo clone "${owner}/${repo}" "${dir}" || return
  fi

  cd "${dir}" || return
}

# init a new application
function _dev::init {
  [[ -f "${_dev_root}/dev.yml" ]] && {
    _dev_print_error "can't reinitialize project: dev.yml already exists"
    return 1
  }

  project="Create a new project with a dev.yml"
  dev_yml="Add dev.yml to the current project"

  _dev_choose action "What do you want to do?" "$project" "$dev_yml"

  case "$action" in
    "$project")
      _dev::init::project
      ;;
    "$dev_yml")
      _dev::init::dev_yml
      ;;
  esac
}

function _dev::init::project {
  rails="Rails"
  react="React"

  _dev_choose project_type "What kind of project would you like to create?" "$rails" "$react"
  _dev_prompt project_name "What should the name of the project be? "

  case "$project_type" in
    "$rails")
      rails new ${project_name}
      cd ${project_name}
      ;;
    "$react")
      npx create-react-app ${project_name}
      cd ${project_name}
      ;;
  esac

  _dev_print "✍️ ${project_type} project generated"
}

function _dev::init::dev_yml {
  cat >dev.yml <<EOF
name: $(basename $(pwd))

EOF

  [[ -f Gemfile ]] && {
    grep -q "up:" dev.yml || echo "up:" >>dev.yml
    ruby_version=$(ruby -e 'puts RUBY_VERSION' 2>/dev/null)
    cat >>dev.yml <<EOF
  - ruby:
      version: ${ruby_version:-2.7.2}
  - bundler
EOF
  }

  [[ -f package.json ]] && {
    grep -q "up:" dev.yml || echo "up:" >>dev.yml
    node_version=$(nvm version 2>/dev/null)
    cat >>dev.yml <<EOF
  - node:
      version: ${node_version:-v14.16.0}
EOF
  }

  _dev_print "✍️ dev.yml generated"
}

# open a url
function _dev::open {
  (( $# > 0 )) || {
    cat >&2 <<EOF
Usage: dev open <target>

Targets:
  gh      Open the repo on GitHub
  issues  Open the repo issues on GitHub
  pr      Open a PR on GitHub
EOF
    return 1
  }

  local target="$1"
  shift

  case "${target}" in
    gh|github)
      gh repo view --web
      ;;
    issue|issues)
      gh issue list --web
      ;;
    pr)
      gh pr create --web
      ;;
    *)
      _dev_print_error "unknown target: ${target}"
      return 1
      ;;
  esac
}

# run
function _dev::run {
  (( $+_dev_commands[build] && $+_dev_commands[run-built] )) && {
    _dev_exec build && _dev_exec run-built "$@"
    return
  }

  (( $+_dev_commands[server] )) && {
    _dev_exec server "$@"
    return
  }

  _dev_print_error "project must define either 'build' and 'run-built', or 'server'"
  return 1
}

# install and start dependencies
function _dev::up {
  _dev_require_project || return

  (
    cd "${_dev_root}" || return

    for i in {1..${#_dev_up}}
    do
      local d="${_dev_up[$i]}"

      eval "${_dev_up_values[$i]}"

      (( $+functions[_dev::up::${d}] )) || {
        _dev_print_warning "unsupported dependency: ${d}"
        continue
      }

      case "${(t)_dev_up_value}" in
        association*)
          "_dev::up::${d}" association "${(kv)_dev_up_value[@]}" || return
          ;;
        array*)
          "_dev::up::${d}" "${_dev_up_value[@]}" || return
          ;;
        scalar*)
          "_dev::up::${d}" "${_dev_up_value}" || return
          ;;
        "")
          "_dev::up::${d}" || return
          ;;
        *)
          _dev_print_error "unexpected type for value: ${(t)_dev_up_value}"
          return 1
          ;;
      esac
    done
    [[ -f "${dev_root}/.gitignore" ]] || {
      mkdir -p "${_dev_root}/.dev"
      echo '*' >"${_dev_root}/.dev/.gitignore"
    }
    date >"${_dev_root}/.dev/mtime"
    _dev_print "🏁 Done."
  )
}

# bundle
function _dev::up::bundler {
  _dev_print "🧳 bundle"
  bundle check || bundle install
}

# custom provisioning step
function _dev::up::custom {
  local name met meet

  [[ "$1" == "association" ]] || {
    _dev_print_error "unrecognized configuration for custom step"
    return 1
  }

  shift

  name=$(_dev_up_value_get name "$@")
  _dev_print "⚙️  $name"

  met=$(_dev_up_value_get met? "$@")
  meet=$(_dev_up_value_get meet "$@")

  sh -c "$met" && return
  sh -c "$meet" && sh -c "$met" && return

  local _status=$?
  _dev_print_error "met? or meet failed for $name"
  return $_status
}

# start docker
function _dev::up::docker {
  docker ps -q >/dev/null 2>&1 || open -g -a Docker.app
}

# install go version
function _dev::up::go {
  local version

  if [[ "$1" == "association" ]]; then
    shift
    version=$(_dev_up_value_get version "$@")
  elif (( $# > 0 )); then
    version=$1
  else
    version=$(curl -s https://golang.org/VERSION?m=text | sed -e 's/^go//')
  fi

  _dev_print "🐹 go $version"

  mkdir -p "$HOME/.golangs/.downloads" || return

  local goroot="$HOME/.golangs/go$version"

  [[ -d "$goroot" && -n "$(ls -A "$goroot")" ]] && {
    print -P "%B%F{green}>>>%f Go is already installed into ${HOME}/.golangs/go$version%b"
    _dev_version set go ${version}
    return 0
  }

  local tarball="go${version}.darwin-amd64.tar.gz"
  local tarball_path="${HOME}/.golangs/.downloads/$tarball"
  local sha256=$(curl -s https://storage.googleapis.com/golang/${tarball}.sha256)

  echo "$sha256  $tarball_path" | shasum -csa 256 - 2>/dev/null || {
    curl -o "$tarball_path" "https://storage.googleapis.com/golang/${tarball}"
    echo "$sha256  $tarball_path" | shasum -ca 256 - || return
  }

  mkdir -p "$goroot" || return
  tar zxf "$tarball_path" --directory "$goroot" --strip-components=1 || return
  source "${functions_source[chgo]}"
  _dev_version set go ${version}
}

# brew install
function _dev::up::homebrew {
  (( $# > 0 )) || {
    _dev_print_warning "no packages specified for homebrew"
    return 0
  }

  [[ "$1" == "association" ]] && {
    _dev_print_error "unexpected association parameter for homebrew"
    return 2
  }

  _dev_print "🍺 $@"

  brew install "$@"
}

# nvm install
function _dev::up::node {
  local version
  local -a packages

  if [[ "$1" == "association" ]]; then
    shift
    version=$(_dev_up_value_get version "$@")
    packages=$(_dev_up_value_get packages "$@")
  elif (( $# > 0 )); then
    version=$1
    packages=( "${_dev_root}" )
  else
    version=stable
    packages=( "${_dev_root}" )
  fi

  _dev_print "%F{green}⬢%f node $version"
  nvm install ${version} || return

  _dev_version set node ${version}

  _dev_print "🧶 yarn"
  npm install --global yarn || return
  [[ -f "${_dev_root}/package.json" ]] || npm init -y >/dev/null || return
  yarn install --silent
}

# ruby-install
function _dev::up::ruby {
  local version

  if [[ "$1" == "association" ]]; then
    shift
    version=$(_dev_up_value_get version "$@")
  elif (( $# > 0 )); then
    version=$1
  else
    version=stable
  fi

  _dev_print "💎 ruby $version"

  case "${version}" in
  stable)
    ruby-install ruby --no-reinstall --cleanup || return
    version=$(chruby | tail -n 1 | sed -e 's/^.*ruby-//')
    ;;
  *)
    ruby-install ruby --no-reinstall --cleanup ${version} || return
    ;;
  esac

  source "${functions_source[chruby]}"
  _dev_version set ruby ${version}
}

#
# zsh hooks
#

autoload -U add-zsh-hook

# update dev and reload dev.yml
add-zsh-hook chpwd _dev_chpwd
function _dev_chpwd() {
  _dev_update
  _dev_reload
}

# detect ruby and go versions
add-zsh-hook precmd detect_versions
function detect_versions {
  local version

  [[ -n ${version::=$(_dev_version get go)} ]] && chgo "$version"
  [[ -n ${version::=$(_dev_version get node)} ]] && nvm use --silent "$version"
  [[ -n ${version::=$(_dev_version get ruby)} ]] && chruby "$version"
}

#
# helper/utility functions
#

function _dev_choose {
  variable=$1
  shift

  echo $1
  shift

  for i in {1..$#@}
  do
    echo "${i}. ${@[$i]}"
  done

  while _dev_prompt choice "choose one: "
  do
    [[ ${choice} =~ "^[0-9]+$" ]] || continue
    (( ${choice} >= 1 && ${choice} <= $#@ )) && break
  done

  eval "typeset -g $variable\"=${@[$choice]}\""
}

function _dev_exec {
  command=$1
  shift

  (
    cd "${_dev_root}" || return
    sh -c "${_dev_commands[${command}]}" "${command}" "$@"
  )
}

function _dev_prompt {
  echo -n "$2"
  read $1
}

# github cli authentication
function _dev_gh_auth {
  gh auth status >/dev/null 2>&1 || {
    local token

    echo "A personal API token is required to access GitHub. You can get one by visiting"
    echo "https://github.com/settings/tokens/new?scopes=repo,read:org&description=dev.plugin"

    echo -n "Please enter your token: "
    read token
    echo "${token}" | gh auth login --hostname github.com --with-token
  }

  gh api user | ruby -rjson -e 'puts JSON.load($stdin)["login"]'
}

# load current dev.yml
function _dev_load {
  unset _dev_name _dev_up _dev_up_values _dev_commands
  _dev_root=$(_dev_path) && {
    typeset -g _dev_name
    typeset -ag _dev_up _dev_up_values
    typeset -Ag _dev_commands
    eval "$(_dev_loader)"
  }
  _dev_loaded_at=$(_dev_mtime "${_dev_root}/dev.yml")
}

function _dev_loader {
  lib="$(dirname "$functions_source[$funcstack[1]]")/lib"

  ruby "${lib}/loader.rb" "${_dev_root}/dev.yml"
}

# determine mtime of source for dev command
function _dev_mtime {
  [[ -f "$1" ]] && date -r "$1" +%s
}

# determine path of parent directory containing dev.yml
function _dev_path {
  local dir
  dir=$(pwd)
  while [[ ${dir} != / ]]; do
    [[ -f ${dir}/dev.yml ]] && {
      echo "${dir}"
      return 0
    }
    dir=$(dirname "${dir}")
  done
  return 1
}

# print message
function _dev_print {
  print -P "%B$@%b"
}

# print error
function _dev_print_error {
  print -P "%F{red}Error:%f $@" >&2
}

# print warning
function _dev_print_warning {
  print -P "%F{yellow}Warning:%f ${@}" >&2
}

# reload dev.yml if changed
function _dev_reload {
  [[ "$(_dev_path)" == "${_dev_root}" && $(_dev_mtime "${_dev_root}/dev.yml") -eq ${_dev_loaded_at} ]] || {
    _dev_load
  }
}

# require project
function _dev_require_project {
  [[ -n "${_dev_root}" ]] || {
    _dev_print "not a project (dev.yml not found)"
    return 1
  }
}

# search a dev up parameter for the named value
function _dev_up_value_get {
  value=$1
  shift

  while (( $# >= 2 )); do
    [[ "$1" == "${value}" ]] && {
      echo $2
      return 0
    }
    shift 2
  done

  return 1
}

# determine time of last successful dev up
function _dev_up_time {
  _dev_mtime "${_dev_root}/.dev/mtime"
}

# reload dev if changed
function _dev_update {
  [[ $(_dev_mtime "${functions_source[dev]}") -eq ${_dev_modified_at} ]] || {
    source "${functions_source[dev]}"
  }
}

# get or set version
function _dev_version {
  local action=$1
  local versiondir="${_dev_root}/.dev/$2"
  local versionfile="${versiondir}/version"

  case $action in
    get)
      [[ -f "$versionfile" ]] && cat "$versionfile"
      ;;
    set)
      mkdir -p "$versiondir"
      echo "$3" >"$versionfile"
      ;;
    *)
      _dev_print_error "Unknown action: $action"
      return 2
      ;;
  esac
}

_dev_modified_at=$(_dev_mtime "${functions_source[dev]}")
_dev_load
