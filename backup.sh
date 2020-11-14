#!/bin/bash

source "$(dirname ${0})/.env"

BACKUP_PID="$(dirname ${0})/.run-${1}.pid"
BACKUP_RUN="$(dirname ${0})/.lastBackup"
BACKUP_LOG="$(dirname ${0})/logs/log-$(date +"%Y-%m").txt"

BACKUP_CRON="--cron"

#
# PROCESS HANLDING
#
function FUNC_PROCESS_HANDLING() {
  if [ -f "${BACKUP_PID}" ]; then
      echo "Process is already running with PID $(cat ${BACKUP_PID})"
      exit 1
  fi

  trap "rm -f -- '${BACKUP_PID}'" EXIT
  echo $$ > "${BACKUP_PID}"
}

#
# TEST: NETWORK
#
function FUNC_TEST_NETWORK() {
  if [ "${BACKUP_PING}" != "" ]; then
    ping -c 1 -t 2 ${BACKUP_PING} 2>/dev/null 1>/dev/null
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
  BACKUP_BATTERY_STATUS="$(ioreg -rc AppleSmartBattery)"
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

case $1 in
  init)
    FUNC_PROCESS_HANDLING $1
    FUNC_TEST_NETWORK

    if [ "${BACKUP_QUOTA}" == "" ]; then
      borg init -v --encryption=keyfile-blake2
    else
      borg init -v --encryption=keyfile-blake2 --storage-quota ${BACKUP_QUOTA}
    fi

    echo ""
    echo "‼️ Save the following lines in a password manager ‼️"
    echo ""

    borg key export --paper
    ;;

  create)
    BACKUP_TIME_NOW="$(date +%s)"

    if [ "${2}" = "${BACKUP_CRON}" ]; then
      touch "${BACKUP_RUN}"

      # Read the timestamp from last run
      BACKUP_TIME_LAST="$(cat "${BACKUP_RUN}" | head -n 1 | sed -e 's/[^0-9]//g')"
      # Defined waiting time until the next run.
      BACKUP_TIME_WAIT="$(bc <<< "${BACKUP_INTERVAL} * 60 * 60 - 60")"

      if [ "${BACKUP_TIME_LAST}" = "" ]; then
        BACKUP_TIME_LAST="0"
      fi

      BACKUP_TIME_DIFF="$(bc <<< "${BACKUP_TIME_NOW} - ${BACKUP_TIME_LAST}")"

      if [ "${BACKUP_TIME_DIFF}" -lt "${BACKUP_TIME_WAIT}" ]; then
        exit 0
      fi

      exec > >(perl -pe 'use POSIX strftime; print strftime "[%Y-%m-%d %H:%M:%S%z] ", localtime' | tee -ai ${BACKUP_LOG})
      exec 2>&1

      echo "## Backup is created"

      FUNC_PROCESS_HANDLING $1
      FUNC_TEST_BATTERY
      FUNC_TEST_NETWORK

      osascript -e 'display notification "Backup is created" with title "Borgbackup"'
    else
      FUNC_PROCESS_HANDLING $1
      FUNC_TEST_NETWORK
    fi

    # Mounted folders are ignored
    BACKUP_MOUNTED=$(df -h | tail -n +2 | awk '{print $9}' | grep -e '^/Users' | sed -e 's|^/|--exclude /|')

    borg create --stats --exclude-from "$(dirname ${0})/.borgignore" \
      ${BACKUP_MOUNTED} \
      ::{hostname}-{now:%Y%m%dT%H%M%S%z} \
      ~/

    if [ "$?" = 0 ]; then
      osascript -e 'display notification "Backup was created" with title "Borgbackup"'
    else
      osascript -e 'display notification "‼️ Backup creation has failed" with title "Borgbackup"'
      exit 1
    fi

    if [ "${2}" = "${BACKUP_CRON}" ]; then
      echo "## Backup was created"
      echo "################################################################################"
      echo -e "${BACKUP_TIME_NOW}\n# $(date -r ${BACKUP_TIME_NOW} +%FT%T%z)" > "${BACKUP_RUN}"
    fi
    ;;

  check)
    if [ "${2}" = "${BACKUP_CRON}" ]; then
      exec > >(perl -pe 'use POSIX strftime; print strftime "[%Y-%m-%d %H:%M:%S%z] ", localtime' | tee -ai ${BACKUP_LOG})
      exec 2>&1

      echo "## Backup is checked"

      FUNC_PROCESS_HANDLING $1
      FUNC_TEST_BATTERY
      FUNC_TEST_NETWORK

      osascript -e 'display notification "Backup is checked" with title "Borgbackup"'
    else
      FUNC_PROCESS_HANDLING $1
      FUNC_TEST_NETWORK
    fi

    BORG_OPS=""
    if [ "${2}" = "--repair" ]; then
      BORG_OPS="${BORG_OPS} ${2}"
    fi

    borg check --verify-data ${BORG_OPS}

    if [ "$?" = 0 ]; then
      osascript -e 'display notification "Backup was checked" with title "Borgbackup"'
    else
      osascript -e 'display notification "‼️ Backup check has failed" with title "Borgbackup"'
      exit 1
    fi

    if [ "${2}" = "${BACKUP_CRON}" ]; then
      echo "## Backup was checked"
      echo "################################################################################"
    fi
    ;;

  list)
    FUNC_PROCESS_HANDLING $1
    FUNC_TEST_NETWORK

    borg list --short
    ;;

  prune)
    if [ "${2}" = "${BACKUP_CRON}" ]; then
      exec > >(perl -pe 'use POSIX strftime; print strftime "[%Y-%m-%d %H:%M:%S%z] ", localtime' | tee -ai ${BACKUP_LOG})
      exec 2>&1

      echo "## Backup is cleaned up"

      FUNC_PROCESS_HANDLING $1
      FUNC_TEST_BATTERY
      FUNC_TEST_NETWORK

      osascript -e 'display notification "Backup is cleaned up" with title "Borgbackup"'
    else
      FUNC_PROCESS_HANDLING $1
      FUNC_TEST_NETWORK
    fi


    borg prune --stats -v --list \
      --prefix='{hostname}-' \
      --keep-last 9 \
      --keep-daily=8 \
      --keep-weekly=5 \
      --keep-monthly=9 \


    if [ "$?" = 0 ]; then
      osascript -e 'display notification "Backup was cleaned up" with title "Borgbackup"'
    else
      osascript -e 'display notification "‼️ Backup clean up has failed" with title "Borgbackup"'
      exit 1
    fi

    if [ "${2}" = "${BACKUP_CRON}" ]; then
      echo "## Backup was cleaned up"
      echo "################################################################################"
    fi
    ;;

  diff)
    FUNC_PROCESS_HANDLING $1
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

    borg diff "::${2}" "${3}"
    ;;

  delete)
    FUNC_PROCESS_HANDLING $1
    FUNC_TEST_NETWORK

    if [ "${2}" = "" ]; then
      echo "Archive is missing"
      echo ""
      echo "${0} delete <archive>"
      exit 1
    fi

    borg delete -v --stats "::${2}"
    ;;

  mount)
    FUNC_PROCESS_HANDLING $1
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

    borg mount "::${2}" "${3}"
    ;;

  umount)
    FUNC_PROCESS_HANDLING $1

    if [ "${2}" = "" ]; then
      echo "Mountpoint is missing"
      echo ""
      echo "${0} umount <mountpoint>"
      exit 1
    fi

    borg umount "${2}"
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
