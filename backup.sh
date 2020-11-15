#!/bin/bash

source "$(dirname ${0})/.env"

BACKUP_PID="$(dirname ${0})/.run-${1}.pid"
BACKUP_LOG="$(dirname ${0})/logs/log-$(date +"%Y-%m").txt"
BACKUP_FILE_CREATE="$(dirname ${0})/.lastBackup"
BACKUP_FILE_PRUNE="$(dirname ${0})/.lastPrune"

BACKUP_CRON="--cron"

#
# LAST RUN HANDLING
#
function FUNC_LAST_RUN() {
  BACKUP_LAST_RUN_NOW="${1}"
  BACKUP_LAST_RUN_FILE="${2}"
  BACKUP_LAST_RUN_INTERVAL="${3}"

  touch "${BACKUP_LAST_RUN_FILE}"

  # Read the timestamp from last run
  BACKUP_LAST_RUN_LAST="$(cat "${BACKUP_LAST_RUN_FILE}" | head -n 1 | sed -e 's/[^0-9]//g')"
  # Defined waiting time until the next run.
  BACKUP_LAST_RUN_WAIT="$(bc <<< "${BACKUP_LAST_RUN_INTERVAL} - 60")"

  if [ "${BACKUP_LAST_RUN_LAST}" = "" ]; then
    BACKUP_LAST_RUN_LAST="0"
  fi

  BACKUP_LAST_RUN_DIFF="$(bc <<< "${BACKUP_LAST_RUN_NOW} - ${BACKUP_LAST_RUN_LAST}")"

  if [ "${BACKUP_LAST_RUN_DIFF}" -lt "${BACKUP_LAST_RUN_WAIT}" ]; then
    exit 0
  fi

}

#
# PROCESS HANLDING
#
function FUNC_PROCESS_HANDLING() {
  if [ -f "${BACKUP_PID}" ]; then
      echo "Process is already running with PID $(cat ${BACKUP_PID})"
      exit 1
  fi

  trap "/bin/rm -f -- '${BACKUP_PID}'" EXIT
  echo $$ > "${BACKUP_PID}"
}

#
# TEST: NETWORK
#
function FUNC_TEST_NETWORK() {
  if [ "${BACKUP_PING}" != "" ]; then
    /sbin/ping -c 1 -t 2 ${BACKUP_PING} 2>/dev/null 1>/dev/null
    if [ "$?" != 0 ]; then
      echo "Device is not online"
      exit 1
    fi
  fi
}

#
# TEST: BATTERY
#
function FUNC_TEST_BATTERY() {
  BACKUP_BATTERY_STATUS="$(/usr/sbin/ioreg -rc AppleSmartBattery)"
  BACKUP_BATTERY_CONNECT="$(echo "${BACKUP_BATTERY_STATUS}" | sed -n -e '/ExternalConnected/s/^.*"ExternalConnected"\ =\ //p')"

  if [ "${BACKUP_BATTERY_CONNECT}" = "No" ]; then
    BACKUP_BATTERY_CURRENT="$(echo "${BACKUP_BATTERY_STATUS}" | sed -n -e '/CurrentCapacity/s/^.*"CurrentCapacity"\ =\ //p')"
    BACKUP_BATTERY_CAPACITY="$(echo "${BACKUP_BATTERY_STATUS}" | sed -n -e '/MaxCapacity/s/^.*"MaxCapacity"\ =\ //p')"
    BACKUP_BATTERY_PERCENT="$(echo $(( BACKUP_BATTERY_CURRENT * 100 / BACKUP_BATTERY_CAPACITY )))"

    if [[ $BACKUP_BATTERY_PERCENT -lt $BACKUP_BATTERY_LIMIT ]]; then
      echo "Battery: Must be charged (${BACKUP_BATTERY_PERCENT}% < ${BACKUP_BATTERY_LIMIT}%)"
      exit 1
    fi
  fi
}

# Create logs folder
mkdir -p "$(dirname ${BACKUP_LOG})"

# Used for last run
BACKUP_TIME_NOW="$(date +%s)"

case $1 in
  init)
    FUNC_PROCESS_HANDLING
    FUNC_TEST_NETWORK

    if [ "${BACKUP_QUOTA}" == "" ]; then
      /usr/local/bin/borg init -v --encryption=keyfile-blake2
    else
      /usr/local/bin/borg init -v --encryption=keyfile-blake2 --storage-quota ${BACKUP_QUOTA}
    fi

    echo ""
    echo "‼️ Save the following lines in a password manager ‼️"
    echo ""

    /usr/local/bin/borg key export --paper
    ;;

  create)
    if [ "${2}" = "${BACKUP_CRON}" ]; then
      exec > >(perl -pe 'use POSIX strftime; print strftime "[%Y-%m-%d %H:%M:%S%z] ", localtime' | tee -ai ${BACKUP_LOG})
      exec 2>&1

      FUNC_LAST_RUN "${BACKUP_TIME_NOW}" "${BACKUP_FILE_CREATE}" "${BACKUP_INTERVAL_CREATE} * 60 * 60"

      FUNC_PROCESS_HANDLING
      FUNC_TEST_BATTERY
      FUNC_TEST_NETWORK

      echo "## Backup is created"
    else
      FUNC_PROCESS_HANDLING
      FUNC_TEST_NETWORK
    fi

    # Mounted folders are ignored
    BACKUP_MOUNTED=$(df -h | tail -n +2 | awk '{print $9}' | grep -e '^/Users' | sed -e 's|^/|--exclude /|')

    /usr/local/bin/borg create --stats --exclude-from "$(dirname ${0})/.borgignore" \
      ${BACKUP_MOUNTED} \
      ::{hostname}-{now:%Y%m%dT%H%M%S%z} \
      ~/

    if [ "$?" != "0" ]; then
      /usr/bin/osascript -e 'display notification "‼️ Backup creation has failed ‼️" with title "Borgbackup"'
      exit 1
    fi

    echo -e "${BACKUP_TIME_NOW}\n# $(date -r ${BACKUP_TIME_NOW} +%FT%T%z)" > "${BACKUP_FILE_CREATE}"

    if [ "${2}" = "${BACKUP_CRON}" ]; then
      echo "## Backup was created"
      echo "################################################################################"
    fi
    ;;

  check)
    if [ "${2}" = "${BACKUP_CRON}" ]; then
      exec > >(perl -pe 'use POSIX strftime; print strftime "[%Y-%m-%d %H:%M:%S%z] ", localtime' | tee -ai ${BACKUP_LOG})
      exec 2>&1

      FUNC_PROCESS_HANDLING
      FUNC_TEST_BATTERY
      FUNC_TEST_NETWORK

      echo "## Backup is checked"

      /usr/bin/osascript -e 'display notification "Backup is checked" with title "Borgbackup"'
    else
      FUNC_PROCESS_HANDLING
      FUNC_TEST_NETWORK
    fi

    BORG_OPS=""
    if [ "${2}" = "--repair" ]; then
      BORG_OPS="${BORG_OPS} ${2}"
    fi

    /usr/local/bin/borg check --verify-data ${BORG_OPS}

    if [ "$?" = 0 ]; then
      /usr/bin/osascript -e 'display notification "Backup was checked" with title "Borgbackup"'
    else
      /usr/bin/osascript -e 'display notification "‼️ Backup check has failed" with title "Borgbackup"'
      exit 1
    fi

    if [ "${2}" = "${BACKUP_CRON}" ]; then
      echo "## Backup was checked"
      echo "################################################################################"
    fi
    ;;

  list)
    FUNC_PROCESS_HANDLING
    FUNC_TEST_NETWORK

    /usr/local/bin/borg list --short
    ;;

  prune)
    if [ "${2}" = "${BACKUP_CRON}" ]; then
      exec > >(perl -pe 'use POSIX strftime; print strftime "[%Y-%m-%d %H:%M:%S%z] ", localtime' | tee -ai ${BACKUP_LOG})
      exec 2>&1

      FUNC_LAST_RUN "${BACKUP_TIME_NOW}" "${BACKUP_FILE_PRUNE}" "${BACKUP_INTERVAL_PRUNE} * 60 * 60 * 24"

      FUNC_PROCESS_HANDLING
      FUNC_TEST_BATTERY
      FUNC_TEST_NETWORK

      echo "## Backup is cleaned up"

      /usr/bin/osascript -e 'display notification "Backup is cleaned up" with title "Borgbackup"'
    else
      FUNC_PROCESS_HANDLING
      FUNC_TEST_NETWORK
    fi


    /usr/local/bin/borg prune --stats -v --list \
      --prefix='{hostname}-' \
      --keep-last 9 \
      --keep-daily=8 \
      --keep-weekly=5 \
      --keep-monthly=9 \


    if [ "$?" = 0 ]; then
      /usr/bin/osascript -e 'display notification "Backup was cleaned up" with title "Borgbackup"'
    else
      /usr/bin/osascript -e 'display notification "‼️ Backup clean up has failed" with title "Borgbackup"'
      exit 1
    fi

    echo -e "${BACKUP_TIME_NOW}\n# $(date -r ${BACKUP_TIME_NOW} +%FT%T%z)" > "${BACKUP_FILE_PRUNE}"

    if [ "${2}" = "${BACKUP_CRON}" ]; then
      echo "## Backup was cleaned up"
      echo "################################################################################"
    fi
    ;;

  diff)
    FUNC_PROCESS_HANDLING
    FUNC_TEST_NETWORK

    if [ "${2}" = "" ]; then
      echo "Archive-1 is missing"
      echo ""
      echo "${0} diff <archive-1> <archive-2>"
      exit 1
    fi

    if [ "${3}" = "" ]; then
      echo "Archive-2 is missing"
      echo ""
      echo "${0} diff <archive-1> <archive-2>"
      exit 1
    fi

    /usr/local/bin/borg diff "::${2}" "${3}"
    ;;

  delete)
    FUNC_PROCESS_HANDLING
    FUNC_TEST_NETWORK

    if [ "${2}" = "" ]; then
      echo "Archive is missing"
      echo ""
      echo "${0} delete <archive>"
      exit 1
    fi

    /usr/local/bin/borg delete -v --stats "::${2}"
    ;;

  mount)
    FUNC_PROCESS_HANDLING
    FUNC_TEST_NETWORK

    if [ "${2}" = "" ]; then
      echo "Archive is missing"
      echo ""
      echo "${0} mount <archive> <mountpoint>"
      exit 1
    fi

    if [ "${3}" = "" ]; then
      echo "Mountpoint is missing"
      echo ""
      echo "${0} mount <archive> <mountpoint>"
      exit 1
    fi

    /usr/local/bin/borg mount "::${2}" "${3}"
    ;;

  umount)
    FUNC_PROCESS_HANDLING

    if [ "${2}" = "" ]; then
      echo "Mountpoint is missing"
      echo ""
      echo "${0} umount <mountpoint>"
      exit 1
    fi

    /usr/local/bin/borg umount "${2}"
    ;;

  *)
    echo "${0} init|list"
    echo "${0} create|check|prune [${BACKUP_CRON}]"
    echo "${0} check --repair"
    echo "${0} diff <archive-1> <archive-2>"
    echo "${0} delete <archive>"
    echo "${0} mount <archive> <mountpoint>"
    echo "${0} umount <mountpoint>"
    ;;
esac
