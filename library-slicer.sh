#!/bin/zsh

set -e

SOURCE_PATTERN="$1"
TARGET_PATH="$2"
BUILD_COMMAND="${3:-make}"

if [ "$SOURCE_PATTERN" = "" -o "$TARGET_PATH" = "" ]; then
  echo "Usage: $0 <SOURCE_PATTERN> <TARGET_PATH> [build command]" >&2
  exit 1
fi

while sleep 0.01; do
  errors="$($BUILD_COMMAND 2>&1 | tee /dev/stderr | grep -e 'fatal error: .*: No such file or directory' | head -n 1)" 
  if [ "$errors" = "" ]; then
    break
  fi

  file="$(echo "$errors" | sed -e 's/.*fatal error: \(.*\): No such file or directory/\1/g')"
  echo FILE: $file

  count="$(zsh -c "ls $SOURCE_PATTERN/'$file'" | tee /dev/stderr | wc -l)"
  if [ "$count" != "1" ]; then
    echo "Ambigous source file." 2>&1
    exit 1
  fi

  src="$(zsh -c "ls $SOURCE_PATTERN/'$file'")"

  cmd="mkdir -p '$TARGET_PATH/${file:h}' && cp -v '$src' '$TARGET_PATH/$file'"
  echo "$cmd" | sed -e 's/ && /;\n/g'

  echo "Press enter to perform the copy. Ctrl-C to abort."
  read any;
  zsh -c "$cmd"
done
