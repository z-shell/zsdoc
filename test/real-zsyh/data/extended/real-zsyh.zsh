# -------------------------------------------------------------------------------------------------
# Copyright (c) 2010-2016 zsh-syntax-highlighting contributors
# All rights reserved.
#
# The only licensing for this file follows.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted
# provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice, this list of conditions
#    and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright notice, this list of
#    conditions and the following disclaimer in the documentation and/or other materials provided
#    with the distribution.
#  * Neither the name of the zsh-syntax-highlighting contributors nor the names of its contributors
#    may be used to endorse or promote products derived from this software without specific prior
#    written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
# FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
# IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
# OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# -------------------------------------------------------------------------------------------------
# -*- mode: zsh; sh-indentation: 2; indent-tabs-mode: nil; sh-basic-offset: 2; -*-
# vim: ft=zsh sw=2 ts=2 et
# -------------------------------------------------------------------------------------------------

# First of all, ensure predictable parsing.
zsh_highlight__aliases=`builtin alias -Lm '[^+]*'`
# In zsh <= 5.2, `alias -L` emits aliases that begin with a plus sign ('alias -- +foo=42')
# them without a '--' guard, so they don't round trip.
#
# Hence, we exclude them from unaliasing:
builtin unalias -m '[^+]*'

# Set $0 to the expected value, regardless of functionargzero.
0=${(%):-%N}
if true; then
  # $0 is reliable
  typeset -g ZSH_HIGHLIGHT_VERSION=$(<"${0:A:h}"/.version)
  typeset -g ZSH_HIGHLIGHT_REVISION=$(<"${0:A:h}"/.revision-hash)
  if [[ $ZSH_HIGHLIGHT_REVISION == \$Format:* ]]; then
    # When running from a source tree without 'make install', $ZSH_HIGHLIGHT_REVISION
    # would be set to '$Format:%H$' literally.  That's an invalid value, and obtaining
    # the valid value (via `git rev-parse HEAD`, as Makefile does) might be costly, so:
    ZSH_HIGHLIGHT_REVISION=HEAD
  fi
fi

# -------------------------------------------------------------------------------------------------
# Core highlighting update system
# -------------------------------------------------------------------------------------------------

# Use workaround for bug in ZSH?
# zsh-users/zsh@48cadf4 http://www.zsh.org/mla/workers//2017/msg00034.html
autoload -U is-at-least
if is-at-least 5.3.2; then
  zsh_highlight__pat_static_bug=false
else
  zsh_highlight__pat_static_bug=true
fi

# Array declaring active highlighters names.
typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS

# Update ZLE buffer syntax highlighting.
#
# Invokes each highlighter that needs updating.
# This function is supposed to be called whenever the ZLE state changes.
_zsh_highlight()
{
  # Store the previous command return code to restore it whatever happens.
  local ret=$?

  # Remove all highlighting in isearch, so that only the underlining done by zsh itself remains.
  # For details see FAQ entry 'Why does syntax highlighting not work while searching history?'.
  # This disables highlighting during isearch (for reasons explained in README.md) unless zsh is new enough
  # and doesn't have the 5.3.1 bug
  if [[ $WIDGET == zle-isearch-update ]] && { $zsh_highlight__pat_static_bug || ! (( $+ISEARCHMATCH_ACTIVE )) }; then
    region_highlight=()
    return $ret
  fi

  setopt localoptions warncreateglobal
  setopt localoptions noksharrays
  local REPLY # don't leak $REPLY into global scope

  # Do not highlight if there are more than 300 chars in the buffer. It's most
  # likely a pasted command or a huge list of files in that case..
  [[ -n ${ZSH_HIGHLIGHT_MAXLENGTH:-} ]] && [[ $#BUFFER -gt $ZSH_HIGHLIGHT_MAXLENGTH ]] && return $ret

  # Do not highlight if there are pending inputs (copy/paste).
  [[ $PENDING -gt 0 ]] && return $ret

  # Reset region highlight to build it from scratch
  typeset -ga region_highlight
  region_highlight=();

  {
    local cache_place
    local -a region_highlight_copy

    # Select which highlighters in ZSH_HIGHLIGHT_HIGHLIGHTERS need to be invoked.
    local highlighter; for highlighter in $ZSH_HIGHLIGHT_HIGHLIGHTERS; do

      # eval cache place for current highlighter and prepare it
      cache_place="_zsh_highlight__highlighter_${highlighter}_cache"
      typeset -ga ${cache_place}

      # If highlighter needs to be invoked
      if ! type "_zsh_highlight_highlighter_${highlighter}_predicate" >&/dev/null; then
        echo "zsh-syntax-highlighting: warning: disabling the ${(qq)highlighter} highlighter as it has not been loaded" >&2
        # TODO: use ${(b)} rather than ${(q)} if supported
        ZSH_HIGHLIGHT_HIGHLIGHTERS=( ${ZSH_HIGHLIGHT_HIGHLIGHTERS:#${highlighter}} )
      elif "_zsh_highlight_highlighter_${highlighter}_predicate"; then

        # save a copy, and cleanup region_highlight
        region_highlight_copy=("${region_highlight[@]}")
        region_highlight=()

        # Execute highlighter and save result
        {
          "_zsh_highlight_highlighter_${highlighter}_paint"
        } always {
          eval "${cache_place}=(\"\${region_highlight[@]}\")"
        }

        # Restore saved region_highlight
        region_highlight=("${region_highlight_copy[@]}")

      fi

      # Use value form cache if any cached
      eval "region_highlight+=(\"\${${cache_place}[@]}\")"

    done

    # Re-apply zle_highlight settings

    # region
    if (( REGION_ACTIVE == 1 )); then
      _zsh_highlight_apply_zle_highlight region standout "$MARK" "$CURSOR"
    elif (( REGION_ACTIVE == 2 )); then
      () {
        local needle=$'\n'
        integer min max
        if (( MARK > CURSOR )) ; then
          min=$CURSOR max=$MARK
        else
          min=$MARK max=$CURSOR
        fi
        (( min = ${${BUFFER[1,$min]}[(I)$needle]} ))
        (( max += ${${BUFFER:($max-1)}[(i)$needle]} - 1 ))
        _zsh_highlight_apply_zle_highlight region standout "$min" "$max"
      }
    fi

    # yank / paste (zsh-5.1.1 and newer)
    (( $+YANK_ACTIVE )) && (( YANK_ACTIVE )) && _zsh_highlight_apply_zle_highlight paste standout "$YANK_START" "$YANK_END"

    # isearch
    (( $+ISEARCHMATCH_ACTIVE )) && (( ISEARCHMATCH_ACTIVE )) && _zsh_highlight_apply_zle_highlight isearch underline "$ISEARCHMATCH_START" "$ISEARCHMATCH_END"

    # suffix
    (( $+SUFFIX_ACTIVE )) && (( SUFFIX_ACTIVE )) && _zsh_highlight_apply_zle_highlight suffix bold "$SUFFIX_START" "$SUFFIX_END"


    return $ret


  } always {
    typeset -g _ZSH_HIGHLIGHT_PRIOR_BUFFER="$BUFFER"
    typeset -gi _ZSH_HIGHLIGHT_PRIOR_CURSOR=$CURSOR
  }
}

# Apply highlighting based on entries in the zle_highlight array.
# This function takes four arguments:
# 1. The exact entry (no patterns) in the zle_highlight array:
#    region, paste, isearch, or suffix
# 2. The default highlighting that should be applied if the entry is unset
# 3. and 4. Two integer values describing the beginning and end of the
#    range. The order does not matter.
_zsh_highlight_apply_zle_highlight() {
  local entry="$1" default="$2"
  integer first="$3" second="$4"

  # read the relevant entry from zle_highlight
  local region="${zle_highlight[(r)${entry}:*]}"

  if [[ -z "$region" ]]; then
    # entry not specified at all, use default value
    region=$default
  else
    # strip prefix
    region="${region#${entry}:}"

    # no highlighting when set to the empty string or to 'none'
    if [[ -z "$region" ]] || [[ "$region" == none ]]; then
      return
    fi
  fi

  integer start end
  if (( first < second )); then
    start=$first end=$second
  else
    start=$second end=$first
  fi
  region_highlight+=("$start $end $region")
}


# -------------------------------------------------------------------------------------------------
# API/utility functions for highlighters
# -------------------------------------------------------------------------------------------------

# Array used by highlighters to declare user overridable styles.
typeset -gA ZSH_HIGHLIGHT_STYLES

# Whether the command line buffer has been modified or not.
#
# Returns 0 if the buffer has changed since _zsh_highlight was last called.
_zsh_highlight_buffer_modified()
{
  [[ "${_ZSH_HIGHLIGHT_PRIOR_BUFFER:-}" != "$BUFFER" ]]
}

# Whether the cursor has moved or not.
#
# Returns 0 if the cursor has moved since _zsh_highlight was last called.
_zsh_highlight_cursor_moved()
{
  [[ -n $CURSOR ]] && [[ -n ${_ZSH_HIGHLIGHT_PRIOR_CURSOR-} ]] && (($_ZSH_HIGHLIGHT_PRIOR_CURSOR != $CURSOR))
}

# Add a highlight defined by ZSH_HIGHLIGHT_STYLES.
#
# Should be used by all highlighters aside from 'pattern' (cf. ZSH_HIGHLIGHT_PATTERN).
# Overwritten in tests/test-highlighting.zsh when testing.
_zsh_highlight_add_highlight()
{
  local -i start end
  local highlight
  start=$1
  end=$2
  shift 2
  for highlight; do
    if (( $+ZSH_HIGHLIGHT_STYLES[$highlight] )); then
      region_highlight+=("$start $end $ZSH_HIGHLIGHT_STYLES[$highlight]")
      break
    fi
  done
}

# -------------------------------------------------------------------------------------------------
# Setup functions
# -------------------------------------------------------------------------------------------------

# Helper for _zsh_highlight_bind_widgets
# $1 is name of widget to call
_zsh_highlight_call_widget()
{
  builtin zle "$@" &&
  _zsh_highlight
}

# Rebind all ZLE widgets to make them invoke _zsh_highlights.
_zsh_highlight_bind_widgets()
{
  setopt localoptions noksharrays
  typeset -F SECONDS
  local prefix=orig-s$SECONDS-r$RANDOM # unique each time, in case we're sourced more than once

  # Load ZSH module zsh/zleparameter, needed to override user defined widgets.
  zmodload zsh/zleparameter 2>/dev/null || {
    print -r -- >&2 'zsh-syntax-highlighting: failed loading zsh/zleparameter.'
    return 1
  }

  # Override ZLE widgets to make them invoke _zsh_highlight.
  local -U widgets_to_bind
  widgets_to_bind=(${${(k)widgets}:#(.*|run-help|which-command|beep|set-local-history|yank)})

  # Always wrap special zle-line-finish widget. This is needed to decide if the
  # current line ends and special highlighting logic needs to be applied.
  # E.g. remove cursor imprint, don't highlight partial paths, ...
  widgets_to_bind+=(zle-line-finish)

  # Always wrap special zle-isearch-update widget to be notified of updates in isearch.
  # This is needed because we need to disable highlighting in that case.
  widgets_to_bind+=(zle-isearch-update)

  local cur_widget
  for cur_widget in $widgets_to_bind; do
    case $widgets[$cur_widget] in

      # Already rebound event: do nothing.
      user:_zsh_highlight_widget_*);;

      # The "eval"'s are required to make $cur_widget a closure: the value of the parameter at function
      # definition time is used.
      #
      # We can't use ${0/_zsh_highlight_widget_} because these widgets are always invoked with
      # NO_function_argzero, regardless of the option's setting here.

      # User defined widget: override and rebind old one with prefix "orig-".
      user:*) zle -N $prefix-$cur_widget ${widgets[$cur_widget]#*:}
              eval "_zsh_highlight_widget_${(q)prefix}-${(q)cur_widget}() { _zsh_highlight_call_widget ${(q)prefix}-${(q)cur_widget} -- \"\$@\" }"
              zle -N $cur_widget _zsh_highlight_widget_$prefix-$cur_widget;;

      # Completion widget: override and rebind old one with prefix "orig-".
      completion:*) zle -C $prefix-$cur_widget ${${(s.:.)widgets[$cur_widget]}[2,3]}
                    eval "_zsh_highlight_widget_${(q)prefix}-${(q)cur_widget}() { _zsh_highlight_call_widget ${(q)prefix}-${(q)cur_widget} -- \"\$@\" }"
                    zle -N $cur_widget _zsh_highlight_widget_$prefix-$cur_widget;;

      # Builtin widget: override and make it call the builtin ".widget".
      builtin) eval "_zsh_highlight_widget_${(q)prefix}-${(q)cur_widget}() { _zsh_highlight_call_widget .${(q)cur_widget} -- \"\$@\" }"
               zle -N $cur_widget _zsh_highlight_widget_$prefix-$cur_widget;;

      # Incomplete or nonexistent widget: Bind to z-sy-h directly.
      *)
         if [[ $cur_widget == zle-* ]] && [[ -z $widgets[$cur_widget] ]]; then
           _zsh_highlight_widget_${cur_widget}() { :; _zsh_highlight }
           zle -N $cur_widget _zsh_highlight_widget_$cur_widget
         else
      # Default: unhandled case.
           print -r -- >&2 "zsh-syntax-highlighting: unhandled ZLE widget ${(qq)cur_widget}"
           print -r -- >&2 "zsh-syntax-highlighting: (This is sometimes caused by doing \`bindkey <keys> ${(q-)cur_widget}\` without creating the ${(qq)cur_widget} widget with \`zle -N\` or \`zle -C\`.)"
         fi
    esac
  done
}

# Load highlighters from directory.
#
# Arguments:
#   1) Path to the highlighters directory.
_zsh_highlight_load_highlighters()
{
  setopt localoptions noksharrays

  # Check the directory exists.
  [[ -d "$1" ]] || {
    print -r -- >&2 "zsh-syntax-highlighting: highlighters directory ${(qq)1} not found."
    return 1
  }

  # Load highlighters from highlighters directory and check they define required functions.
  local highlighter highlighter_dir
  for highlighter_dir ($1/*/); do
    highlighter="${highlighter_dir:t}"
    [[ -f "$highlighter_dir${highlighter}-highlighter.zsh" ]] &&
      . "$highlighter_dir${highlighter}-highlighter.zsh"
    if type "_zsh_highlight_highlighter_${highlighter}_paint" &> /dev/null &&
       type "_zsh_highlight_highlighter_${highlighter}_predicate" &> /dev/null;
    then
        # New (0.5.0) function names
    elif type "_zsh_highlight_${highlighter}_highlighter" &> /dev/null &&
         type "_zsh_highlight_${highlighter}_highlighter_predicate" &> /dev/null;
    then
        # Old (0.4.x) function names
        if false; then
            # TODO: only show this warning for plugin authors/maintainers, not for end users
            print -r -- >&2 "zsh-syntax-highlighting: warning: ${(qq)highlighter} highlighter uses deprecated entry point names; please ask its maintainer to update it: https://github.com/zsh-users/zsh-syntax-highlighting/issues/329"
        fi
        # Make it work.
        eval "_zsh_highlight_highlighter_${(q)highlighter}_paint() { _zsh_highlight_${(q)highlighter}_highlighter \"\$@\" }"
        eval "_zsh_highlight_highlighter_${(q)highlighter}_predicate() { _zsh_highlight_${(q)highlighter}_highlighter_predicate \"\$@\" }"
    else
        print -r -- >&2 "zsh-syntax-highlighting: ${(qq)highlighter} highlighter should define both required functions '_zsh_highlight_highlighter_${highlighter}_paint' and '_zsh_highlight_highlighter_${highlighter}_predicate' in ${(qq):-"$highlighter_dir${highlighter}-highlighter.zsh"}."
    fi
  done
}


# -------------------------------------------------------------------------------------------------
# Setup
# -------------------------------------------------------------------------------------------------

# Try binding widgets.
_zsh_highlight_bind_widgets || {
  print -r -- >&2 'zsh-syntax-highlighting: failed binding ZLE widgets, exiting.'
  return 1
}

# Resolve highlighters directory location.
_zsh_highlight_load_highlighters "${ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR:-${${0:A}:h}/highlighters}" || {
  print -r -- >&2 'zsh-syntax-highlighting: failed loading highlighters, exiting.'
  return 1
}

# Reset scratch variables when commandline is done.
_zsh_highlight_preexec_hook()
{
  typeset -g _ZSH_HIGHLIGHT_PRIOR_BUFFER=
  typeset -gi _ZSH_HIGHLIGHT_PRIOR_CURSOR=
}
autoload -U add-zsh-hook
add-zsh-hook preexec _zsh_highlight_preexec_hook 2>/dev/null || {
    print -r -- >&2 'zsh-syntax-highlighting: failed loading add-zsh-hook.'
  }

# Load zsh/parameter module if available
zmodload zsh/parameter 2>/dev/null || true

# Initialize the array of active highlighters if needed.
[[ $#ZSH_HIGHLIGHT_HIGHLIGHTERS -eq 0 ]] && ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)

# Restore the aliases we unned
eval "$zsh_highlight__aliases"
builtin unset zsh_highlight__aliases

# Set $?.
true


# Add to HOOK the given FUNCTION.
# HOOK is one of chpwd, precmd, preexec, periodic, zshaddhistory,
# zshexit, zsh_directory_name (the _functions subscript is not required).
#
# With -d, remove the function from the hook instead; delete the hook
# variable if it is empty.
#
# -D behaves like -d, but pattern characters are active in the
# function name, so any matching function will be deleted from the hook.
#
add-zsh-hook() {
# Add to HOOK the given FUNCTION.
# HOOK is one of chpwd, precmd, preexec, periodic, zshaddhistory,
# zshexit, zsh_directory_name (the _functions subscript is not required).
#
# With -d, remove the function from the hook instead; delete the hook
# variable if it is empty.
#
# -D behaves like -d, but pattern characters are active in the
# function name, so any matching function will be deleted from the hook.
#
# Without -d, the FUNCTION is marked for autoload; -U is passed down to
# autoload if that is given, as are -z and -k.  (This is harmless if the
# function is actually defined inline.)

emulate -L zsh

local -a hooktypes
hooktypes=(
  chpwd precmd preexec periodic zshaddhistory zshexit
  zsh_directory_name
)
local usage="Usage: add-zsh-hook hook function\nValid hooks are:\n  $hooktypes"

local opt
local -a autoopts
integer del list help

while getopts "dDhLUzk" opt; do
  case $opt in
    (d)
    del=1
    ;;

    (D)
    del=2
    ;;

    (h)
    help=1
    ;;

    (L)
    list=1
    ;;

    ([Uzk])
    autoopts+=(-$opt)
    ;;

    (*)
    return 1
    ;;
  esac
done
shift $(( OPTIND - 1 ))

if (( list )); then
  typeset -mp "(${1:-${(@j:|:)hooktypes}})_functions"
  return $?
elif (( help || $# != 2 || ${hooktypes[(I)$1]} == 0 )); then
  print -u$(( 2 - help )) $usage
  return $(( 1 - help ))
fi

local hook="${1}_functions"
local fn="$2"

if (( del )); then
  # delete, if hook is set
  if (( ${(P)+hook} )); then
    if (( del == 2 )); then
      set -A $hook ${(P)hook:#${~fn}}
    else
      set -A $hook ${(P)hook:#$fn}
    fi
    # unset if no remaining entries --- this can give better
    # performance in some cases
    if (( ! ${(P)#hook} )); then
      unset $hook
    fi
  fi
else
  if (( ${(P)+hook} )); then
    if (( ${${(P)hook}[(I)$fn]} == 0 )); then
      typeset -ga $hook
      set -A $hook ${(P)hook} $fn
    fi
  else
    typeset -ga $hook
    set -A $hook $fn
  fi
  autoload $autoopts -- $fn
fi
}


#
# Test whether $ZSH_VERSION (or some value of your choice, if a second argument
# is provided) is greater than or equal to x.y.z-r (in argument one). In fact,
# it'll accept any dot/dash-separated string of numbers as its second argument
# and compare it to the dot/dash-separated first argument. Leading non-number
# parts of a segment (such as the "zefram" in 3.1.2-zefram4) are not considered
# when the comparison is done; only the numbers matter. Any left-out segments
# in the first argument that are present in the version string compared are
# considered as zeroes, eg 3 == 3.0 == 3.0.0 == 3.0.0.0 and so on.
#
is-at-least() {
#
# Test whether $ZSH_VERSION (or some value of your choice, if a second argument
# is provided) is greater than or equal to x.y.z-r (in argument one). In fact,
# it'll accept any dot/dash-separated string of numbers as its second argument
# and compare it to the dot/dash-separated first argument. Leading non-number
# parts of a segment (such as the "zefram" in 3.1.2-zefram4) are not considered
# when the comparison is done; only the numbers matter. Any left-out segments
# in the first argument that are present in the version string compared are
# considered as zeroes, eg 3 == 3.0 == 3.0.0 == 3.0.0.0 and so on.
#
# Usage examples:
# is-at-least 3.1.6-15 && setopt NO_GLOBAL_RCS
# is-at-least 3.1.0 && setopt HIST_REDUCE_BLANKS
# is-at-least 586 $MACHTYPE && echo 'You could be running Mandrake!'
# is-at-least $ZSH_VERSION || print 'Something fishy here.'
#
# Note that segments that contain no digits at all are ignored, and leading
# text is discarded if trailing digits follow, because this was the meaning
# of certain zsh version strings in the early 2000s.  Other segments that
# begin with digits are compared using NUMERIC_GLOB_SORT semantics, and any
# other segments starting with text are compared lexically.

emulate -L zsh

local IFS=".-" min_cnt=0 ver_cnt=0 part min_ver version order

min_ver=(${=1})
version=(${=2:-$ZSH_VERSION} 0)

while (( $min_cnt <= ${#min_ver} )); do
  while [[ "$part" != <-> ]]; do
    (( ++ver_cnt > ${#version} )) && return 0
    if [[ ${version[ver_cnt]} = *[0-9][^0-9]* ]]; then
      # Contains a number followed by text.  Not a zsh version string.
      order=( ${version[ver_cnt]} ${min_ver[ver_cnt]} )
      if [[ ${version[ver_cnt]} = <->* ]]; then
        # Leading digits, compare by sorting with numeric order.
        [[ $order != ${${(On)order}} ]] && return 1
      else
        # No leading digits, compare by sorting in lexical order.
        [[ $order != ${${(O)order}} ]] && return 1
      fi
      [[ $order[1] != $order[2] ]] && return 0
    fi
    part=${version[ver_cnt]##*[^0-9]}
  done

  while true; do
    (( ++min_cnt > ${#min_ver} )) && return 0
    [[ ${min_ver[min_cnt]} = <-> ]] && break
  done

  (( part > min_ver[min_cnt] )) && return 0
  (( part < min_ver[min_cnt] )) && return 1
  part=''
done
}
