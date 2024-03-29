<h1 align="center">
    <img src="https://raw.githubusercontent.com/z-shell/.github/main/profile/img/logo.png" alt="Logo" width="80" height="80" />
    <p>Doxygen For Shell Scripts</p>
</h1>

- [Introduction](#introduction)
- [Installation](#installation)
- [Usage](#usage)
- [Examples](#examples)
- [Few Rules](#few-rules)

## Introduction

Parses `Zsh` and `Bash` scripts, outputs `Asciidoc` document with:

- list of functions, including autoload functions,
- call trees of functions and script body,
- comments for functions,
- features used for each function and script body (features like: `eval`, `read`, `vared`, `shopt`, etc.),
- distinct marks for hooks registered with `add-zsh-hook` (Zsh),
- list of exported variables,
- list of used exported variables and the variable's origin (i.e., possibly another script).

Call trees support cross-file invocations, i.e. when a script calls a function defined in other files.

They are written in `Zshell` language.

## Installation

The default install path-prefix is `/usr/local`.

```shell
git clone https://github.com/z-shell/zsdoc
cd zsdoc
make
sudo make install
```

For custom `PREFIX` variable in `make` invocation:

```SystemVerilog
# 'sudo' may be required to install

make install PREFIX=~/opt/local
install -c -d ~/opt/local/share/zsdoc
install -c -d ~/opt/local/share/doc/zsdoc

cp build/zsd build/zsd-transform build/zsd-detect build/zsd-to-adoc ~/opt/local/bin
cp README.md NEWS LICENSE ~/opt/local/share/doc/zsdoc
cp zsd.config ~/opt/local/share/zsdoc
```
```SystemVerilog
➜ cd ~/opt/local
➜ tree .
        ├── bin
        │   ├── zsd
        │   ├── zsd-detect
        │   ├── zsd-to-adoc
        │   └── zsd-transform
        │
        └── share
           ├── doc
           │   └── zsdoc
           │       ├── LICENSE
           │       ├── NEWS
           │       └── README.md
           │
           └── zsdoc
               └── zsd.config
```

Other available `make` variables are: `INSTALL` (to customize the install command),
`BIN_DIR`, `SHARE_DIR`, `DOC_DIR`.

## Usage

```shell
zsd [-h/--help] [-v/--verbose] [-q/--quiet] [-n/--noansi] [--cignore <pattern>] {file1} [file2] ...

The files will be processed and their documentation will be generated
in subdirectory `zsdoc' (with meta-data in subdirectory `data').
```

```shell
Options:
-h/--help      Usage information
-v/--verbose   More verbose operation-status output
-q/--quiet     No status messages
-n/--noansi    No colors in terminal output
--cignore      Specify which comment lines should be ignored
-f/--fpath     Paths are separated by: pointing to directories with functions
--synopsis     Text to be used in the SYNOPSIS section. Line break "... +\n", paragraph "...\n\n"
--scomm        Strip comment char "#" from function comments
--bash         Output slightly tailored to Bash specifics (instead of Zsh specifics)
```

Example `--cignore` options:

```sh
# Ignore comments like: # FUNCTION: usage {{{
--cignore  '\#[[:blank:]]FUNCTION:[[:blank:]]*[[:blank:]]{{{*'
```

```sh
# Ignore comments like: # FUN: usage {{{
--cignore '(\#[[:blank:]]FUN(C|CTION|):[[:blank:]]*[[:blank:]]{{{*|[[:blank:]]\#[[:blank:]]}}}*)'
```

```sh
File is parsed for synopsis block, which can be e.g.:
# synopsis {{{my synopsis, can be multi-line}}}
```

Another block that is parsed is commenting on environment variables. It consists of multiple
"VAR_NAME -> var description" lines and results in a table in the output AsciiDoc document.

Example:

```sh
# env-vars {{{
# PATH -> paths to executables
# MANPATH -> paths to manuals }}}
```

Change the default brace block-delimeters with `--blocka`, and `--blockb`. The block body should be AsciiDoc.

## Examples

[example 1](https://github.com/z-shell/zsdoc/blob/main/examples/zsh-syntax-highlighting.zsh.adoc),
[example 2](https://github.com/z-shell/zsdoc/blob/main/examples/zsh-autosuggestions.zsh.adoc)
(also in **PDF**:
[example 1](https://raw.githubusercontent.com/z-shell/zsdoc/main/examples/zsh-syntax-highlighting.zsh.pdf),
[example 2](https://raw.githubusercontent.com/z-shell/zsdoc/main/examples/zsh-autosuggestions.zsh.pdf)).

## Few Rules

Here are a few rules helping to use `zsdoc` in your project:

1. Write function comments before the function. Empty lines between comments and functions are allowed.
2. If you use special comments, e.g. `vim` (or `emacs-origami`) **folds**, you can ignore these lines with `--cignore` (see [Usage](https://github.com/z-shell/zsdoc#usage)).
3. If it's possible to avoid `eval`, then do that – `zsdoc` will analyze more code.
4. Currently, functions defined in functions are ignored, but this will change shortly.
5. I've greatly optimized the new `Zsh` version (`5.4.2`) for data processing – `zsdoc` parses long sources very fast starting from that `Zsh` version.
6. If you have multiple `Zsh` versions installed, then (for example) set `zsh_control_bin="/usr/local/bin/zsh-5.4.2"` in `/usr/local/share/zsdoc/zsd.config`.
7. Be aware that to convert a group of scripts, you simply need `zsd file1.zsh file2.zsh ...` – cross-file function invocations will work automatically, and multiple `*.adoc` files will be created.
8. Create `Makefile` with `doc` target, that does `rm -rf zsdoc/data; zsd -v file1.zsh ...`. Documentation will land in the `zsdoc` directory.
9. Directory `zsdoc/data` holds meta-data used to create `asciidoc` documents (`*.adoc` files). You can remove it or analyze it yourself.
10. Obtain **PDFs** with [Asciidoctor](http://asciidoctor.org/) tool via: `asciidoctor -b pdf -r asciidoctor-pdf file1.zsh.adoc`. Install `Asciidoctor` with: `gem install asciidoctor-pdf --pre`. (Check out [ZI's Makefile](https://github.com/z-shell/docs/blob/main/code/Makefile).)
11. HTML: `asciidoctor script.adoc`.
12. Obtain manual pages with `Asciidoc` package via: `a2x -L --doctype manpage --format manpage file1.zsh.adoc` (`asciidoc` is a common package; its `a2x` command is a little slow).
13. Github supports `Asciidoc` documents and renders them automatically.
