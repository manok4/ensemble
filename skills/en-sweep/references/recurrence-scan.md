# Recurrence scan (step 8b)

Read when step 8b runs. It turns a correction reviewers keep making into one
routed tech-debt entry, so the next occurrence is stopped by a check instead of
another comment. Opt-in: it runs only when `.ensemble/config.local.yaml` sets
`sweep.recurrence_scan: true`.

## Config

```yaml
sweep:
  recurrence_scan: true          # default false
  recurrence_window_days: 60     # default 60
```

## Procedure

1. **Window.** Today minus `recurrence_window_days`. Every run re-reads the whole
   window rather than only what merged since the last sweep, so two matching PRs
   on either side of a sweep still land in one scan. Deduplication absorbs the
   overlap.
2. **Fetch.** `$SKILL_DIR/scripts/ensemble-review-history --since <window-start>`.
   Exit 3 means no PR merged in the window: skip the step. Exit 1 means the scan
   could not run: record `recurrence_scan: failed (<stderr>)` in the sweep
   summary and continue the rest of the sweep.
3. **Cluster** comments by the correction they make, not their wording: "don't
   return the ORM row" and "this returns an ORM instance again" are one cluster.
   Ignore style nits and one-off questions.
4. **Keep** clusters spanning two or more distinct PRs.
5. **Route** each kept cluster with `enforcement-layers.md`. L5 clusters file
   nothing.
6. **File** through `$SKILL_DIR/scripts/ensemble-td-append`, with
   `--source "en-sweep recurrence"`, the PR numbers in `--location`
   (`PRs #101, #130`), and a rule key. Run `--list-keys` first and reuse the key
   of an open entry that describes the same correction; that keeps clustering
   stable across runs. Exit 4 means the cluster is already tracked. Exit 1 means
   the tracker is not in the canonical layout: list the proposals in the sweep
   summary instead.
7. **Summary.** One line per cluster: key, layer, PRs, and the TD-ID or
   `exists TD<N>`.

The tracker lives under `docs/`, so this step keeps sweep's doc-only contract.
