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
    (
      cd "${_dev_root}" || return
      sh -c "${_dev_commands[${command}]}" "${command}" "$@"
    )
    return $?
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

  case "${target}" in
    gh)
      gh repo view --web
      ;;
    pr)
      gh pr create --web
      ;;
    *)
      _dev_print_error "Unable to open unknown target: ${target}"
      return 1
      ;;
  esac
}

# install and start dependencies
function _dev::up {
  for d in ${_dev_up}
  do
    eval "${_dev_dependencies[${d}]}"

    (( $+functions[_dev::up::${d}] )) || {
      _dev_print_warning "Ignoring unsupported dependency: ${d}"
      continue
    }

    case "${(t)_dev_up_value}" in
      association*)
        "_dev::up::${d}" association "${(kv)_dev_up_value[@]}"
        ;;
      array*)
        "_dev::up::${d}" "${_dev_up_value[@]}"
        ;;
      scalar*)
        "_dev::up::${d}" "${_dev_up_value}"
        ;;
      "")
        "_dev::up::${d}"
        ;;
      *)
        _dev_print_error "Unexpected type for value: ${(t)_dev_up_value}"
        return 1
        ;;
    esac
  done
}

# brew install
function _dev::up::homebrew {
  (( $# > 0 )) || {
    _dev_print_warning "No packages specified for homebrew"
    return 0
  }

  [[ "$1" == "association" ]] && {
    _dev_print_error "Unexpected association parameter for homebrew"
    return 2
  }

  _dev_print "🍺 $@"

  brew install "$@"
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

  _dev_print "💎 $version"

  case "${version}" in
  stable)
    ruby-install ruby --no-reinstall || return
    version=$(chruby | tail -n 1 | sed -e 's/^.*ruby-//')
    ;;
  *)
    ruby-install ruby --no-reinstall ${version} || return
    ;;
  esac

  source "${functions_source[chruby]}"
  _dev_version set ruby ${version}
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

  _dev_print "🐹 $version"

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
  [[ -n ${version::=$(_dev_version get ruby)} ]] && chruby "$version"
  [[ -n ${version::=$(_dev_version get go)} ]] && chgo "$version"
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
    echo "${token}" | gh auth login --hostname github.com --with-token
  }

  gh api user | ruby -rjson -e 'puts JSON.load($stdin)["login"]'
}

# load current dev.yml
function _dev_load {
  _dev_root=$(_dev_path) && {
    typeset -g _dev_name
    typeset -ag _dev_up
    typeset -Ag _dev_commands _dev_dependencies
    eval "$(_dev_loader)"
    _dev_print "💻 $_dev_name"
  }
  _dev_loaded_at=$(_dev_yml_mtime)
}

function _dev_loader {
  ruby -ryaml -rshellwords -rjson - "${_dev_root}" <<'LOADER'
root = ARGV.first
yaml = YAML.load_file(File.join(root, "/dev.yml")) || {}
name = yaml.fetch("name", File.dirname(root))
up = yaml.fetch("up", [])
commands = yaml.fetch("commands", {})
puts "_dev_name=#{Shellwords.escape(name)}"
puts "_dev_up=("
up.each do |dependency|
  case dependency
  when Hash
    puts %(  #{dependency.keys.first})
  when Array
    puts %(  #{dependency.first})
  else
    puts %(  #{dependency})
  end
end
puts ")"
puts "_dev_dependencies=("
up.each do |dependency|
  case dependency
  when Hash
    key, value = dependency.first
    assignment = case value
    when Hash
      hash = value.map { |k,v| "[#{k}]=#{Shellwords.escape(v)}" }.join(' ')
      "unset _dev_up_value; local -A _dev_up_value=( #{hash} )"
    when Array
      array = value.map { |v| Shellwords.escape(v) }.join(' ')
      "unset _dev_up_value; local -a _dev_up_value=( #{array} )"
    else
      string = Shellwords.escape(value.to_s)
      "unset _dev_up_value; local _dev_up_value=#{string}"
    end
    puts %(  [#{key}]=#{Shellwords.escape(assignment)})
  when Array
    key, value = dependency
    assignment = case value
    when Hash
      hash = value.map { |k,v| "[#{k}]=#{Shellwords.escape(v)}" }.join(' ')
      "unset _dev_up_value; local -A _dev_up_value=( #{hash} )"
    when Array
      array = value.map { |v| Shellwords.escape(v) }.join(' ')
      "unset _dev_up_value; local -a _dev_up_value=( #{array} )"
    else
      string = Shellwords.escape(value.to_s)
      "unset _dev_up_value; local _dev_up_value=#{string}"
    end
    puts %(  [#{key}]=#{Shellwords.escape(assignment)})
  else
    puts %(  [#{dependency}]="unset _dev_up_value")
  end
end
puts ")"
puts "_dev_commands=("
commands.each do |name, script|
  script = script["run"] if script.is_a?(Hash)
  if script.nil?
    warn "missing command: #{name}"
    next
  end
  script = %(#{script} "$@") if script.lines.size == 1 && !script.include?('$@') && !script.include?('$*')

  puts %(  [#{name}]=#{Shellwords.escape(script)})
end
puts ")"
LOADER
}

# determine mtime of source for dev command
function _dev_mtime {
  date -r "${functions_source[dev]}" +%s
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
  [[ "$(_dev_path)" == "${_dev_root}" && $(_dev_yml_mtime) -eq ${_dev_loaded_at} ]] || {
    _dev_load
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

# reload dev if changed
function _dev_update {
  [[ $(_dev_mtime) -eq ${_dev_modified_at} ]] || {
    source "${functions_source[dev]}"
  }
}

# determine mtime of current dev.yml
function _dev_yml_mtime {
  date -r "${_dev_root}/dev.yml" +%s 2>/dev/null
}

_dev_modified_at=$(_dev_mtime)
_dev_load
