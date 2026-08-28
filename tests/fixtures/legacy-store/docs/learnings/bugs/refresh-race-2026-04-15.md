---
title: "Refresh token race within the rotation window"
applies_when: "Two requests from one user can race during token rotation"
date: 2026-04-15
category: bugs
tags: [auth, race-condition]
related:
  - docs/learnings/patterns/single-flight-2026-03-20.md
status: active
---
Concurrent refreshes both passed the freshness check.
