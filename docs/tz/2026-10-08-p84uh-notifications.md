# dcfg-p84uh — notification fixes

## U1
Owner 08.10 R018: exactly two changes, direct implementation, no executor.
Architecture: retain existing watchdog and archive; change form curl timeout from 10 to 30 seconds and GIT_ASKPASS from invocation path to the live tools/bin/code-archive. No restart, config or secret edits.
Acceptance: bash syntax passes; isolated existing check_form with live GET returns302; archive tools returns ok=1 err=0 using the live executable; submit this scoped atom once. Disk belongs to dcfg-q2o1e; prior parity evidence remains valid. Historic503 cause remains UNVERIFIED and is outside the narrowed owner acceptance.
Rollback: revert these two assignments through normal delivery.
