# What each watch state means

`ensemble-ship-watch` blocks until the PR reaches a state worth acting on, then
returns `SHIP_WATCH_STATE` with its evidence. This is the mapping from that
state to what `/en-ship`'s watch step does with it.

`checks-settled` means every check has a conclusion, **not** that they passed. A
red check is a settled state the caller repairs; reporting "not clean" as a
non-zero exit would make an ordinary CI failure indistinguishable from an
inability to look at the PR at all, which is the defect this whole path exists
to avoid.

| `SHIP_WATCH_STATE` | Exit | What this step does |
|---|---|---|
| `checks-settled`, reason `checks-green` | 0 | Fetch findings once (below). No findings → exit `clean`. |
| `checks-settled`, reason `checks-failed` | 0 | A red check is settled, not an error: repair it. `SHIP_WATCH_FAILED_NAMES` names which. |
| `merged` / `closed` | 0 | Exit `settled-externally`, **after the open-findings sweep below**. |
| `head-moved` | 0 | **Cancel a stale tick**: this tick's CI results are dead, because they describe a commit that is no longer the head. Discard them and re-run the watch. |
| `doctor-failed` / `gh-error` | 1 | Exit `blocked`, quoting `SHIP_WATCH_REASON` and `SHIP_WATCH_DETAIL`. No repair attempted. |
| `timeout` | 2 | Exit `escalated`, naming what was still pending. |
