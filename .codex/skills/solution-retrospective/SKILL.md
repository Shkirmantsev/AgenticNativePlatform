---
name: solution-retrospective
description: "Run after a task that succeeded only after false starts, incorrect assumptions, reverted patches, repeated failed verification, or discovery of a clearly better later approach. Use it to persist durable learning with minimal noise: repo-specific guidance goes into the nearest AGENTS.md, cross-repo reusable guidance goes into an existing or new personal skill only when there is strong evidence. Do not use for simple tasks that were solved directly."
---

# Purpose

Use this skill **after** the main task is solved when there was meaningful course-correction. The goal is to prevent repeating the same avoidable mistakes without creating noisy rules or bloated skills.

# Decision rubric

Classify the lesson into exactly one of these buckets:

1. **Repo-specific durable guidance**
   - The lesson depends on this codebase, directory layout, local commands, conventions, CI behavior, or architecture.
   - Action: update the nearest relevant `AGENTS.md` with a short rule.

2. **Cross-repo reusable workflow**
   - The lesson is a reusable process that would help in many repositories.
   - Action: update an existing **personal** skill if one already fits.
   - Create a new personal skill only if the pattern is concrete, reusable, and not already covered.

3. **Weak / one-off signal**
   - Temporary outage, flaky dependency, credentials issue, incidental typo, or a fact already enforced elsewhere.
   - Action: do nothing.

# Process

1. Write a 3-part mini-retrospective using `assets/retrospective-template.md`:
   - what was tried first
   - why it was wrong or suboptimal
   - what worked better and why
2. Decide whether the lesson is repo-specific, personal-skill-worthy, or too weak.
3. Prefer the **smallest durable change**:
   - add one short AGENTS rule
   - or update one existing personal skill
   - or create one small new personal skill
4. Keep the diff reviewable.
5. In the final note, summarize:
   - the wrong approach
   - the better approach
   - what was persisted, if anything

# Hard rules

- Do not let this retrospective block delivering the requested solution.
- Do not create a skill from a single trivial incident.
- Do not duplicate content already present in AGENTS or an existing skill.
- Do not turn repo-specific quirks into personal skills.
- If evidence is weak, persist nothing.

# Optional helpers

- Use `scripts/classify_learning.py` for a checklist-based recommendation.
- Use `references/persistence-rubric.md` when unsure where the lesson belongs.
