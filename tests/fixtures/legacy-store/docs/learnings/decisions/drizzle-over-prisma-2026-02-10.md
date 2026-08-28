---
title: "Chose Drizzle over Prisma for edge-runtime support"
applies_when: "Choosing an ORM for a project targeting edge runtimes"
date: 2026-02-10
category: decisions
tags: [database, orm]
related: []
status: active
---
Prisma's engine did not run on Workers. Drizzle compiles to plain SQL.
