#!/usr/bin/env bash

set -u -e

if [ $# -lt 3 ]; then
  echo "$0 [old pattern] [new text] [files...]" 1>&2
  exit 1
fi


old_pattern="$1"
new_text="$2"
shift 2


case "$( basename "$0" )" in
  'pattern-rename.sh')
    command='mv -fv' ;;
  'pattern-copy.sh')
    command='cp -rfv' ;;
  'pattern-link.sh')
    command='ln -sfv' ;;
  *)
    if [[ -z "${RENAME_CMD-}" ]]; then
      echo "$0: Unsure how to handle \"$(basename "$0")\". Rename script or set \$RENAME_CMD." 1>&2
      exit 1
    fi
    ;;
esac

if [[ "${RENAME_CMD-}" ]]; then
  command="$RENAME_CMD"
fi

revise_name() {
  sed -E "s\`$old_pattern\`$new_text\`g"
}


old_files="$(printf '%s\n' "$@" | sort -u)"
old_count="$(echo "$old_files" | grep -c .)"

if [[ "$old_count" -eq 0 ]]; then
  echo "$0: No files match the given pattern! Please check it and try again." 1>&2
  exit 1
fi

new_files="$(echo "$old_files" | revise_name)"
new_count="$(echo "$new_files" | sort -u | grep -c .)"

if [ "$old_count" -gt "$new_count" ]; then
  echo "$0: The current pattern would result in the loss of $(($old_count-$new_count)) files! Please check it and try again." 1>&2
  exit 1
fi

echo "$old_files" | while read file; do
  new_file="$(echo "$file" | revise_name)"
  if [[ "$new_file" != "$file" ]]; then
    $command "$file" "$new_file"
  fi
done
