# AGENTS.md

## Working style

- Deliver the requested solution first.
- When a task required course-correction, a false start, a reverted approach, repeated failing tests, or a later clearly better approach, run `$solution-retrospective` before ending the task.
- Keep the retrospective short and action-oriented.

## Persistence rules

- Put **repo-specific durable guidance** in this repository's nearest `AGENTS.md`.
- Put **cross-repo reusable workflows** in a **personal skill**, not in this repo skill directory.
- Prefer **updating an existing rule or skill** over creating a new one.
- Create a new skill only when the pattern is reusable, concrete, and likely to save future work.
- Do not create noise: no new skill for one-off mistakes, temporary outages, or facts already enforced by tests/linters.

## Retrospective trigger examples

Run `$solution-retrospective` when one or more are true:

- The first design choice was wrong and had to be replaced.
- The first patch passed partially but violated project conventions.
- Several files were read or changed unnecessarily before the correct path became clear.
- A better verification method was discovered late.
- The same kind of mistake appeared more than once in the task.

## Update rules

When updating this file:

- Add only durable rules.
- Keep additions specific and short.
- Place rules near the scope where they apply.
- Prefer command examples and path hints over vague prose.
