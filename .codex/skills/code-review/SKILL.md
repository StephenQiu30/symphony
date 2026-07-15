---
name: code-review
description: Perform an automated code review of a ticket and PR during the Agent Review phase.
---

# Code Review

This skill is invoked when a Linear issue transitions into the `Agent Review` state.
Your role as the reviewing agent is to rigorously evaluate the submitted work for completeness, correctness, and adherence to acceptance criteria before it reaches a human.

## Review Process

1. **Understand Context:**
   - Read the Linear issue details and thoroughly review the `## Codex Workpad` checklist.
   - Identify the stated Acceptance Criteria and Validation requirements.

2. **Define Acceptance Before Reviewing:**
   - Locate the project execution documents directly governing the task, including linked requirements, designs, plans, and task documents.
   - Merge those requirements with the Linear issue and Workpad `Acceptance Criteria` and `Validation` sections without weakening any source requirement.
   - Before executing checks, create a numbered acceptance list (`AC-01`, `AC-02`, ...) with the source, expected result, method, and required evidence for every item.
   - Treat missing or conflicting execution documents and criteria that cannot be verified as blocked acceptance items.

3. **Verify Every Item:**
   - Look at the git diff and commit history.
   - Review acceptance items in number order and record actual evidence plus exactly one result: `passed`, `failed`, or `blocked`.
   - Do not stop after the first failure; complete every acceptance item that remains executable so the review exposes all gaps in one pass.
   - Inspect implementation logic for requirement gaps, regressions, security or data-flow bugs, and false completion.
   - Do not accept checked Workpad boxes as evidence without independently verifying them.

4. **Make a Decision:**
   - **Reject (Rework):** If any acceptance item failed, is blocked, lacks evidence, or any functional finding remains:
     1. Leave clear and actionable feedback in the Workpad or as PR comments.
     2. Move the issue state to `Rework`.
     3. Restore the original developer's `agent:*` label using the `linear` skill (e.g., if you are `agent:claude` and the original dev was `agent:codex`, change the label back to `agent:codex`).
   - **Approve:** Only if every acceptance item passed with reviewable evidence and no functional finding remains:
     1. Move the issue state to `Human Review` for final human approval.

## Guardrails
- **Do not write or refactor the code yourself** during this review. Your job is to verify and send it back to the implementer if incomplete.
- **Trust but verify**: Do not take checked boxes in the Workpad at face value. Inspect the code or test execution evidence.
- **Do not weaken requirements**: Missing, conflicting, or unverifiable criteria cannot be silently interpreted as passed.
