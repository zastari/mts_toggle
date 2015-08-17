#!/bin/bash
. mts_toggle.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_return() {
    local _r
    local _e
    _e=$(${1})
    _r=$?
    if [[ ${_r} == ${2} ]]; then
        echo -en "${GREEN}PASS${NC}: "
    else
        echo -en "${RED}FAIL${NC}: "
    fi
    echo "${1} (Returned: ${_r}  Expected: ${2})"
}


assert_emit() {
    local _e
    _e=$(${1})
    if [[ ${_e} == ${2} ]]; then
        echo -en "${GREEN}PASS${NC}: "
    else
        echo -en "${RED}FAIL${NC}: "
    fi
    echo "${1} (Emitted: ${_e}  Expected: ${2})"
}


setup() {
    mysql -e "SET GLOBAL slave_parallel_workers = 8"
    mysql -e "START SLAVE"
    rm -f "${worker_file}"
}

setup

##### Test slave_sql_thread
echo "Test slave_sql_thread stop|start|status"
assert_return "slave_sql_thread stop" 0
assert_return "slave_sql_thread stop" 1         # stop fails if already stopped
assert_emit "slave_sql_thread status" stopped
assert_return "slave_sql_thread start" 0
assert_return "slave_sql_thread start" 1        # start fails if already started
assert_emit "slave_sql_thread status" started
assert_return "slave_sql_thread foo" 1          # invalid arg
echo

setup

echo "Test slave_sql_thread sync"
assert_return "slave_sql_thread sync" 1         # sync fails if sql_thread started
assert_return "slave_sql_thread stop" 0
assert_return "slave_sql_thread sync" 0
assert_emit "slave_sql_thread status" stopped
echo

setup

##### Test slave_workers
echo "Test slave_workers"
assert_return "slave_workers get_file" 1        # get_file fails if file doesn't exist
assert_return "slave_workers set_file" 0
assert_emit "cat ${worker_file}" 8
assert_emit "slave_workers get_running" 8
assert_return "slave_workers set_running" 1     # set_running fails if missing arg
assert_return "slave_workers set_running 0" 0
assert_emit "slave_workers get_running" 0
assert_return "slave_workers set_file" 1        # set_file fails if slave_workers get_running is 0
assert_return "slave_workers get_file" 0
assert_return "slave_workers foo" 1
echo

setup

##### Test mts_toggle
echo "Test mts_toggle enable is nop if slave_workers get_running > 0"
assert_return "mts_toggle enable" 0
assert_emit "slave_workers get_running" 8
assert_emit "slave_sql_thread status" started
echo

setup

echo "Test mts_toggle enable fails with nop if slave_worker get_file fails"
assert_return "slave_workers set_running 0" 0
assert_return "mts_toggle enable" 1
assert_emit "slave_sql_thread status" started
echo

setup

echo "Test mts_toggle disable fails with nop if slave_workers get_running = 0"
assert_return "slave_workers set_running 0" 0
assert_return "mts_toggle disable" 0
assert_emit "slave_sql_thread status" started
echo

setup

echo "Test mts_toggle disable"
assert_return "mts_toggle disable" 0
assert_emit "slave_sql_thread status" started
assert_emit "slave_workers get_running" 0
assert_emit "cat ${worker_file}" 8
echo

echo "Test mts_toggle enable"
assert_return "mts_toggle enable" 0
assert_emit "slave_sql_thread status" started
assert_emit "slave_workers get_running" 8
assert_return "cat ${worker_file}" 1
