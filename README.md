Multi-Threaded Slave Toggle
===========================

This script safely disables and re-enables Multi-Threaded slaves in MySQL. When disabling MTS, it stops the slave SQL_THREAD, starts it with UNTIL SQL_AFTER_MTS_GAPS, and then restarts the thread again once these gaps close.

Usage
-----

mts_toggle.sh (enable|disable)
 * disable multi-threaded replication
 * enable a previously disabled multi-threaded replication environment

License
-------

BSD

Author Information
------------------

Tyler Mitchell
