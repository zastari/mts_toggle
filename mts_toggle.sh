#!/bin/bash
# Manage slave threads in a Multi-threaded slave without GTID
# Author: Tyler Mitchell
# Usage: mts_toggle.sh (disable|enable)
worker_file=slave_parallel_workers.count


# Function slave_sql_thread. Controls the running state of the Slave SQL_THREAD
# Args:
#   $1: (stop|start|sync)  [required]
#       stop: Stops the Slave SQL_Thread
#       start: Starts the Slave SQL_Thread
#       sync: Starts the Slave SQL_THREAD with SQL_AFTER_MTS_GAPS to ensure that all
#             MTS gaps are closed
#       status: Emits "started" if SQL_Thread is running, "stopped" if it isn't and
#               generates an error otherwise
# Returns: 0 if the state transition in $1 completes successfully, 1 otherwise.
slave_sql_thread() {
    case "${1}" in
    "stop")
        if [[ $(slave_sql_thread status) == "stopped" ]];  then
            echo "[ERROR] Could not stop slave SQL_THREAD: Thread already stopped"
            return 1
        fi

        if mysql -e "STOP SLAVE SQL_THREAD"; then
            echo "[INFO] Slave SQL_THREAD stopped successfully"
            return 0
        else
            echo "[ERROR] Failure stopping slave SQL_THREAD: Stop command returned non-zero exit status"
            return 1
        fi
    ;;
    "start")
        if [[ $(slave_sql_thread status) == "started" ]]; then
            echo "[ERROR] Could not start slave SQL_THREAD: Thread already started"
            return 1
        fi

        if mysql -e "START SLAVE SQL_THREAD"; then
            echo "[INFO] Starting slave SQL_THREAD"
            return 0
        else
            echo "[ERROR] Slave SQL_THREAD did not start successfully."
            return 1
        fi
    ;;
    "sync")
        if [[ $(slave_sql_thread status) == "started" ]]; then
            echo "[ERROR] Could not sync slave gaps: Slave SQL_THREAD already started"
            return 1
        fi

        mysql -e "START SLAVE SQL_THREAD UNTIL SQL_AFTER_MTS_GAPS"
        echo "[INFO] Starting Slave SQL_THREAD until MTS gaps are closed"

        local _wait=0
        while [[ $(slave_sql_thread status) == "started" ]]; do 
            let "_wait++"
            sleep 1
        done

        echo "[INFO] Slave MTS Gaps synchronized after ${_wait} seconds"
        return 0
    ;;
    "status")
        local _sql_status=$(mysql -e 'SHOW SLAVE STATUS\G' | awk '/Slave_SQL_Running:/ { print $2 }')
        if [[ ${_sql_status} == "Yes" ]]; then
            echo "started"
            return 0
        elif [[ ${_sql_status} == "No" ]]; then
            echo "stopped"
            return 0
        else
            echo "[ERROR] Slave SQL thread in an indeterminate state"
            return 1
        fi
    ;;
    *)
        echo "[ERROR] Invalid argument sent to slave_sql_thread. Sent: ${1}. Expected: (start|stop|sync)"
        return 1
    ;;
    esac
}


# Function slave_workers: Manage changing @@slave_parallel_workers
# Args:
#   $1: (get_file|set_file|get_running|set_running) [required]
#       get_file: Emit @@slave_parallel_workers_count from file
#       set_file: Write @@slave_parallel_workers count to file
#       get_running: Emit currently running value of @@slave_parallel_workers from MySQL
#       set_running: Set @@GLOBAL.slave_parallel_workers to $2
# Returns: 0 if $1 completes successfully. get_running emits the current value but has type void
slave_workers() {
    case "${1}" in
    "get_file")
        local _worker_count=$(<"${worker_file}")
        if ! [[ ${_worker_count} =~ ^[0-9]+$ ]]; then
            echo "[ERROR] Worker count not integer or not found when reading ${worker_file}"
            return 1
        fi
        echo ${_worker_count}
        return 0
    ;;
    "set_file")
        local _worker_count=$(slave_workers get_running)
        if [[ ${_worker_count} == "0" ]]; then
            echo "[ERROR] Slave worker count is 0 when storing worker count to file"
            return 1
        fi
    
        if echo "${_worker_count}" > "${worker_file}"; then
            echo "[INFO] Slave worker count, ${_worker_count}, written to ${worker_file}"
            return 0
        else
            echo "[ERROR] Error writing slave worker count to ${worker_file}"
            return 1
        fi
    ;;
    "get_running")
        echo "$(mysql -Bse 'SELECT @@slave_parallel_workers')"
    ;;
    "set_running")
        if ! [[ ${2} =~ ^[0-9]+$ ]]; then
            echo "[ERROR] Worker count in input position 2 not integer or not found"
            return 1
        fi

        mysql -Bse "SET GLOBAL slave_parallel_workers = ${2}"
        return $?
    ;;
    *)
        echo "[ERROR] Invalid argument sent to slave_workers. Sent: ${1}. Expected: (set_file|get_file|get_running)"
        return 1
    ;;
    esac
}


# Function mts_toggle: Orchestrate enabling or disabling parallel replication
# Args:
#   $1: (disable|enable) [required]
#       disable: Disable MTS if it is currently enabled
#       enable: Enables MTS if it is currently disabled
# Returns: 0 if $1 completes or the slave SQL_THREAD is stopped, 1 otherwise
mts_toggle() {
    if [[ $(slave_sql_thread status) == "stopped" ]]; then
        echo "[WARNING] Slave SQL_THREAD stopped. No action will be taken."
        return 0
    fi

    case "${1}" in
    "disable")
        if [[ $(slave_workers get_running) == "0" ]]; then
            echo "[WARNING] slave parallel workers already disabled. No action will be taken."
            return 0
        fi
        slave_sql_thread stop && \
        slave_workers set_file && \
        slave_sql_thread sync && \
        slave_workers set_running 0 && \
        echo "[INFO] Slave SQL_THREAD started with $(slave_workers get_running) threads" && \
        slave_sql_thread start && \
        return 0
    ;;
    "enable")
        if [[ $(slave_workers get_running) > "0" ]]; then
            echo "[WARNING] slave parallel workers already enabled. No action will be taken."
            return 0
        fi

        local _stored_worker_count
        if ! _stored_worker_count=$(slave_workers get_file); then
            echo "[ERROR] failed reading the stored @@slave_parallel_workers count from ${worker_file}"
            return 1
        fi

        slave_sql_thread stop && \
        slave_workers set_running ${_stored_worker_count} && \
        slave_sql_thread start && \
        echo "[INFO] Slave SQL_THREAD started with $(slave_workers get_running) threads" && \
        rm -f ${worker_file} && \
        return 0
    ;;
    *)
        echo "[ERROR] Invalid argument. Sent: ${1}. Expected: (disable|enable)"
        return 1
    ;;
    esac
    return 1
}


# Only execute if this script is not sourced
[ "${0}" = "${BASH_SOURCE}" ] && mts_toggle $1
