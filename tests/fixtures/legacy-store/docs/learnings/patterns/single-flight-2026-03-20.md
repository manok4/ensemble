---
title: "Single-flight cache for per-user side-effecting operations"
applies_when: "An operation must run at most once per key with concurrent callers awaiting one result"
date: 2026-03-20
category: patterns
tags: [concurrency, cache]
related:
  - docs/learnings/bugs/refresh-race-2026-04-15.md
status: active
---
Collapse concurrent calls onto one in-flight promise.
