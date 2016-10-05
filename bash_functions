#helper functions to search, edit, and execute history, updated 20150410

_select_filters=$(printf '%s\n' {,f}h{grep,choose,sel,echo,freq})
HPREFIX='^ *[0-9]+ +'

_content_color=$'\033[0;33m'
_edit_color=$'\033[0;31m'
_prompt_color=$'\033[0;37;0m'
_execute_color=$_prompt_color

_read_line() {
  local prompt="$1"
  local initialial_text="$2"
  local final_text=''
  if [ -x "$(which rlwrap)" ]; then
    local color_prompt="$_prompt_color$prompt$_edit_color"
    final_text=$(rlwrap -o -P "$initialial_text" bash -c "echo -n '$color_prompt' 1>&2; cat")
    echo -n "$_execute_color" 1>&2
  else
    read -e -r -p "$prompt" -i "$initialial_text" final_text
  fi && _print_string "$final_text"
}

#(used in place of 'echo' in case an argument happens to be "-e", etc.)
_print_string() {
  #(the value of 'IFS' matters here, e.g., for path concatenation)
  printf '%s\n' "$*"
}

_clean_history() {
  local pattern=$1
  if [ "$pattern" ]; then
    HISTTIMEFORMAT= history | egrep -- "$pattern"
  else
    HISTTIMEFORMAT= history
  fi
}

_last_line() {
  _clean_history | tail -1
}

_delete_history() {
  for l in $lines; do
    history -d $l || break
  done
}

_hist_grep() {
  local pattern="$1"
  shift
  local unset IFS
  _clean_history "$pattern" | while read -r n line; do
    echo "$n:$line"
  done | "$@"
}

_hist_choose() {
  line=$(
    local IFS=$'\n'
    [ "$3" ] && take="-n$3"
    lines=( $("$1" "$2" | egrep -vf <(_print_string "$_select_filters") | head $take) )
    unset IFS
    echo -n "$_content_color" 1>&2
    select cmd in "${lines[@]}"; do
      _print_string "$cmd"
      break
    done )
  _read_line 'edit: ' "$line"
}

_hist_sel() {
  local choose="$1"
  shift
  local _cmd_num=$((HISTCMD-1))
  #(remove current command upon [Ctrl]+C)
  trap 'history -d $_cmd_num; trap SIGINT; return' SIGINT
  line=$("$choose" "$@")
  #(pop handler)
  trap SIGINT
  if [ $? -eq 0 ]; then
    [ "$line" ] && history -s "$line"
    eval "$line"
  else
    history -d $((HISTCMD-1))
  fi
}


_hist_echo() {
  local choose="$1"
  shift
  line=$("$choose" "$@")
  if [ $? -eq 0 ]; then
    read -e -p "redirect: " redirect && eval cat /dev/stdin "$redirect" < <(_print_string "$line")
  fi
}

_hist_by_recency() {
  sort -t: -k2,2 -su | sort -t: -k1,1 -sg | cut -d: -f2- | tac
}

hgrep() {
  _hist_grep "$1" _hist_by_recency
}

_hchoose() {
  _hist_choose hgrep "$@"
}

hsel() {
  _hist_sel _hchoose "$@"
}

hecho() {
  _hist_echo _hchoose "$@"
}


#'cd' shortcut added 20131214

ncd() {
  [ $# -eq 0 ] && return 0

  if [ $# -gt 1 ]; then
    local goto=$1
    shift
  else
    local goto=$(pwd)
  fi

  goto=$(\
    for i in $@; do
      if [ "${i::1}" = '-' ]; then
        i=${i:1:${#i}-1}
        local rev=-r
      fi
      local new=$(ls -d "$goto"/*/ 2> /dev/null | sort $rev | sed "$i"'!d')
      if ! { [ "$new" ] && cd "$new"; }; then
        echo "bad directory number '$i' in '$goto'" 1>&2
        echo
        break
      else
        goto=$(pwd)
        _print_string "$goto"
      fi
    done | tail -n1)

  [ "$goto" ] && cd "$goto" || return 1
}


#directory expansion based on 'ncd' added 20140709

ndir() {
  ( ncd "$@" && builtin pwd )
}


#iterated upward directory traversal, added 20150303

ucd() {
  local count=$1
  local IFS='/'
  local path_all=($(pwd))
  if [ "${count::1}" = '-' ]; then
    count=${count:1:${#count}-1}
    path="${path_all[*]:0:count+1}"
  else
    path="${path_all[*]:0:${#path_all[@]}-count}"
  fi
  if [ "$path" ]; then
    cd "$path"
  fi
}


#incremental cd, added 20150721

icd() {
  local previous="$OLDPWD"
  cd "$@" && OLDPWD="$previous"
}


#substitution cd, added 20150925

scd() {
  local old="$1"
  local new="$2"
  new_path="$(pwd | sed -r 's`'"$old"'`'"$new"'`g')"
  cd "$new_path"
}


#cd upward to component, added 20160205

cdto() {
  local basename="$1"
  if [ ! "$basename" ]; then
    cd '/'
    return
  fi
  local IFS='/'
  local path_all=($(pwd))
  while ((${#path_all[@]})) && [ "${path_all[-1]}" != "$basename" ]; do
    path_all=("${path_all[@]:0:${#path_all[@]}-1}")
  done
  if ! ((${#path_all[@]})); then
    echo "no path component named '$basename'." 1>&2
    return 1
  fi
  cd "${path_all[*]}"
}


#follow chain of directory-with-1-subdirectory, added 20150228

follow() {
  local here="$(pwd)"
  while :; do
    if [ "$(ls | grep -c .)" -ne 1 ] || [ ! -d "$(ls)" ]; then
      if [ $# -gt 0 ]; then
        cd "$1" || break
        shift
        continue
      else
        break
      fi
    fi
    local next="$(ls -d */ 2> /dev/null | head -1)"
    [ "$next" ] || break
    cd "$next"
  done
  #(makes sure last directory is accurate)
  cd "$here"
  if [ $# -eq 0 ]; then
    cd ~-
  else
    return 1
  fi
}


#find a relative path, added 20140717

_fix_path() {
  local IFS='/'
  local old_path=($*)
  local new_path=()

  for d in "${old_path[@]}"; do
    case "$d" in
      ''|'.')
        continue
      ;;
      '..')
        if [ "${#new_path[@]}" -eq 0 ]; then
          new_path+=('..')
        elif [ "${new_path[${#new_path[@]}-1]}" = '..' ]; then
          new_path+=('..')
        else
          new_path=("${new_path[@]::${#new_path[@]}-1}")
        fi
      ;;
      *)
        new_path+=("$d")
      ;;
    esac
  done

  _print_string "${new_path[@]}"
}

_default_path() {
  _print_string "$(realpath "$(pwd)")/"
}

relpath() {
  if [ $# -ne 2 ]; then
    echo "${FUNCNAME[0]} [from directory] [to directory/file]" 1>&2
    return 1
  fi

  local IFS='/'
  local from=( $(_fix_path "$( [ "${1::1}" = '/' ] || _default_path )$1") )
  local to=( $(  _fix_path "$( [ "${2::1}" = '/' ] || _default_path )$2") )
  unset IFS

  local i=0
  local new_path=

  while [ "${from[i]}" ] && [ "${from[i]}" = "${to[i]}" ]; do
    : $((i++))
  done

  local IFS='/'
  new_path="${to[*]:i:${#to[@]}-i}"
  unset IFS

  while :; do
    [ -n "${from[i++]}" ] || break
    [ "$new_path" ] && new_path="/$new_path"
    new_path="..$new_path"
  done

  [ "$new_path" ] && _print_string "$new_path" || echo '.'
}


#process all but the top line of input, updated 20150410

skiphead() {
  local IFS=$'\n'
  read -r h && _print_string "$h"
  unset IFS
  "$@"
}


#remove commands from history, updated 20150410

oops() {
  local unset IFS
  history -d $((HISTCMD-1))
  if [ ! "$1" ]; then
    read -r _cmd_num line < <(_last_line)
    #(remove current command upon [Ctrl]+C)
    trap '_delete_history $_cmd_num; trap SIGINT; return' SIGINT
    line2=$(_read_line 'edit: ' "$line")
    if [ $? -eq 0 ]; then
      trap SIGINT
      history -s "$line2"
      eval "$line2"
    fi
    trap SIGINT
    return $?
  else
    local line_data=$(_clean_history "$1")
    local lines=$(
      _print_string "$line_data" | while read -r n line; do
        echo "$n"
      done | tac
    )
    if [ "$lines" ]; then
      echo -n "$_content_color" 1>&2
      _print_string "$line_data" | while read -r n line; do
        _print_string "$line"
      done | sort | uniq -c | sort -gr | ${PAGER-less} 1>&2
      echo -n "$_prompt_color" 1>&2
      IFS=' ' read -p 'Press [Enter] to proceed...' -N1 -d' ' q
      if [ "$q" != $'\n' ]; then
        echo "Canceled" 1>&2
        return 1
      else
        echo "Deleting..." 1>&2
      fi
    fi
  fi
  _delete_history $lines
}


#added 20150228

mute() {
  "$@" 2> /dev/null
}


#shared history, added 20160617

_check_history_commands() {
  if [ ! -x "$HISTORY_COLLECTOR" ]; then
    echo "$HISTORY_COLLECTOR is not executable." 1>&2
    return 1
  fi
  if [ ! -x "$(which daemon)" ]; then
    echo "daemon command is not executable." 1>&2
    return 1
  fi
}

_start_history_daemon() {
  if [ -z "$HISTORY_COLLECTOR" ]; then
    echo "History Collector not configured; call use_common_history." 1>&2
    return 1
  fi
  _check_history_commands || return 1
  daemon -F "$HOME/.history-collector.pid" -- "$HISTORY_COLLECTOR" --mode=daemon
  while ! [ -S "$HOME/.hc_ipc" ]; do
    echo -en 'Waiting for history-collector.py...\r' 1>&2
    sleep 1
  done
}

use_history_collector() {
  HISTORY_COLLECTOR=$1
  [ "$HISTORY_COLLECTOR" ] || HISTORY_COLLECTOR="$HOME/bin/history-collector.py"
  _check_history_commands || return 1
  for command in '_start_history_daemon' '_write_history'; do
    echo "$PROMPT_COMMAND" | fgrep -q "$command" || PROMPT_COMMAND+="$command;"
  done

  #override from above
  HPREFIX='^'

  _hist_unsorted() {
    cut -d: -f2-
  }

  #override from above
  hgrep() {
    _hist_grep "$1" _hist_unsorted
  }

  #override from above
  _clean_history() {
    _start_history_daemon && _read_history "$@"
  }

  #override from above
  _delete_history() {
    printf '%s\n' "$@" | "$HISTORY_COLLECTOR" --mode=delete
  }

  #override from above
  _last_line() {
    "$HISTORY_COLLECTOR" --mode=last < /dev/null
  }

  _write_history() {
    history -a >(egrep -vx '#[0-9]+' | "$HISTORY_COLLECTOR" --mode=write)
  }

  _read_history() {
    printf '%s\n' "$@" | "$HISTORY_COLLECTOR" --mode=read
  }

  save_history() {
    echo "$1" | "$HISTORY_COLLECTOR" --mode=save
  }

  restore_history() {
    echo "$1" | "$HISTORY_COLLECTOR" --mode=restore
  }
}
