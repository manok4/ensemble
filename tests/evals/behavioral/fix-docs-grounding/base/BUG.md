# Bug: most timeout formats are rejected

`timeoutMs({ timeout: '1.5h' })`, `'2 days'` and `'250ms'` all throw `unsupported timeout`. Config durations must accept every format the `ms` package accepts. `ms` is already a dependency, but nothing calls it yet.
