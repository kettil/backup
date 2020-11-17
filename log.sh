#!/bin/bash

source "$(dirname ${0})/.env"

# Create logs folder
mkdir -p "$(dirname ${BACKUP_FILE_LOG})"

# Check to see if a pipe exists on stdin.
if [ -p /dev/stdin ]; then
  while IFS= read line; do
    echo "$(date +%FT%T%z) | ${line}" >> ${BACKUP_FILE_LOG}
    echo "${line}"
  done
else
  echo "No input was found on stdin, skipping!"
fi
