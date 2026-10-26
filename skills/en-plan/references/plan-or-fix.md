# Plan or fix

Read by `/en-plan` when it right-sizes a request, and by `/en-fix` at triage and again on the real diff. Both skills read this one list, so a request one of them refuses is a request the other accepts.

**A plan earns its cost when it settles something before code is written.** Size does not decide it. There is no file or line count: a rename across eight files needs no plan, and a two-line change to token refresh does.

## Plan when any of these holds

1. **An open decision.** Something the user should settle before code: which architecture, a behaviour trade-off, or more than one reasonable reading that leads to a different design. Unclear wording with no design behind it, such as which of two error messages to show, is one question `/en-fix` asks before editing, not a plan.
2. **A risk surface.** Authentication, payments, migrations, external contracts, or a destructive data operation. These are the small changes that most want a written plan and a peer pass.
3. **Parts that must land in order, or that a reviewer could judge apart.** An expand, migrate, contract sequence, or a unit whose interface a later unit calls. Several commits alone do not count: a refactor that makes room and the change that uses it is one change.
4. **More than one session.** Work that will not be finished and reviewed in one sitting, where the plan file is the handoff across a context reset.
5. **A design doc.** The request comes from `docs/designs/*.md`. Only `/en-plan`'s promotion closes a design out, so any other route leaves it `status: open` and back in `/en-brainstorm`'s resume pool.

## Otherwise, `/en-fix`

None holds: the change goes to `/en-fix`, however many files or commits it takes. `/en-fix` is manual-invoke only, so a skill names the command, `/en-fix <request>`, and never invokes it.

State the call in one line with the condition that decided it, for example "plan: touches the session-token migration" or "fix: one concern, no open decisions". The user can override it either way.
