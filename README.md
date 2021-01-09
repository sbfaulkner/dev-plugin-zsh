# dev plugin

This plugin provides a lightweight version of Shopify's internal dev tool.

## Commands

* `clone` <repo>    - Clone a repo from GitHub.

## Custom Commands

Project-specific commands are defined via a `dev.yml` file in the current directory or a parent of that directory. Commands are defined with their names as keys under the top-level `commands` key.

For example:

```
commands:
  style:
    ...
  build:
    ...
  test:
    ...
```

### Command Definitions

A command's properties are defined as a set of key-value pairs. The supported properties are:

* `run`     - A shell command to be run when the command is invoked (required).
* `desc`    - A description of the command (optional).
* `aliases` - A set of aliases which can be used to invoke the command (optional).

For example:

```
commands:
  style:
    desc: Check style of source files.
    run: bundle exec rubocop -D
    aliases: ['lint']
```

In place of the set of properties, a simple string value may be used as a short-form notation to define the shell command to be run.

For example:

```
commands:
  test: go test ./...
```

### Running Commands

Project-specific commands are invoked the same way built-in commands are run.

For example:

```
$ dev test -short
```

When running the script any additional parameters passeed on the command line will be appended to end of the command. An explicit `$@` or `$*` will override this behaviour when present within the shell command.

## Installation

The [GitHub CLI](https://cli.github.com) needs to be installed in order to support GitHub integration (eg. `dev clone …`). On OS X with Homebrew, this can be done with `brew install gh`.
