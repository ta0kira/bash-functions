#!/usr/bin/env bash

set -u -e

command=${1:-}
shift || true

if [[ -z "${HISTORY_COLLECTOR_FILE-}" ]]; then
  HISTORY_COLLECTOR_FILE=$HOME/.history.db
fi

if [[ -z "${SQLITE3_REGEX_LIB-}" ]]; then
  SQLITE3_REGEX_LIB=/usr/lib/sqlite3/pcre.so
fi

table_name=History
command_col=Command
count_col=UseCount
last_col=LastUse
usage_weight=300

exec_history() {
  cat | sqlite3 "$@" "$HISTORY_COLLECTOR_FILE" 2> /dev/null
}

init_history() {
  if [[ ! -r "$HISTORY_COLLECTOR_FILE" ]]; then
    exec_history <<END
      CREATE TABLE $table_name (
          $command_col TEXT NOT NULL,
          $count_col INT NOT NULL,
          $last_col INT NOT NULL,
          PRIMARY KEY (Command)
        );
END
  fi
}

escape() {
  echo "$@" | sed "s/'/''/g"
}

try_insert() {
  exec_history <<END
    INSERT INTO $table_name (
      $command_col,
      $count_col,
      $last_col
    ) VALUES (
      '$1',
      1,
      $2
    );
END
}

try_update() {
  exec_history <<END
    UPDATE $table_name SET
      $count_col = $count_col+1,
      $last_col = $2
    WHERE $command_col = '$1';
END
}

handle_insert() {
  if [[ $# -ne 1 ]]; then
    echo "$0 insert \"command\"" 1>&2
    exit 1
  fi
  local command=$(escape "$1")
  local last_use=$(date +%s)
  init_history
  try_insert "$command" "$last_use" || try_update "$command" "$last_use"
}

handle_search() {
  if [[ $# -ne 2 ]]; then
    echo "$0 search [limit] \"pattern\"" 1>&2
    exit 1
  fi
  if [[ "$1" ]]; then
    local limit="LIMIT $1"
  else
    local limit=''
  fi
  local pattern=$(escape "$2")
  if [[ -r "$SQLITE3_REGEX_LIB" ]]; then
    exec_history -cmd ".load $SQLITE3_REGEX_LIB" <<END
      SELECT $last_col+$usage_weight*$count_col AS Rank, $command_col
      FROM $table_name
      WHERE Command REGEXP '$pattern'
      ORDER BY Rank DESC
      $limit;
END
  else
    exec_history <<END
      SELECT $last_col+$usage_weight*$count_col AS Rank, $command_col
      FROM $table_name
      WHERE Command GLOB '$pattern'
      ORDER BY Rank DESC
      $limit;
END
  fi | cut -d'|' -f 2-
}

handle_delete() {
  if [[ $# -ne 1 ]]; then
    echo "$0 delete \"command\"" 1>&2
    exit 1
  fi
  local command=$(escape "$1")
  exec_history <<END
    DELETE FROM $table_name
    WHERE $command_col = '$command';
END
}

case "$command" in
  insert)
    handle_insert "$@"
  ;;
  search)
    handle_search "$@"
  ;;
  delete)
    handle_delete "$@"
  ;;
  *)
    echo "$0 [command] (args...)" 1>&2
    exit 1
  ;;
esac
