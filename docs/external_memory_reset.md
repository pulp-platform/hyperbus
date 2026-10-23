# External Memory Reset

Drive memory's active-low reset from a platform GPIO or reset manager. The removed
`hyper_reset_no` port is a breaking interface change across all controller variants.

At power-on, block users until controller startup and device power-up/reset recovery
finish. Controller and memory resets need not release together.

Before memory reset, quiesce all users, offered/accepted transactions, CSR accesses,
barriers and backend recovery. Keep them quiescent through the device's required
reset pulse and recovery. Restore lost device CR settings and initialize/invalidate
affected RAM before resuming; controller replay does not program device CRs.

Controller/PHY reset does not reset memory. External memory reset is not detected
and does not restart the controller startup wait: the platform must enforce device
timing and recovery. Reset during traffic can leave a partial operation; it does
not make the interrupted access atomic.
