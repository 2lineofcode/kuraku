# ---
name: git-commit
description: Inspect, stage, and create a safe Git commit that matches the repository's recent commit-message style. Use when the user asks to commit current work, wants a commit message based on git log, or needs a careful review of staged, modified, and untracked files before committing.
---

# Git Commit

Create one intentional local commit from the requested changes. Preserve unrelated work, do not push, and do not amend unless the user explicitly asks.

## Workflow

1. Read applicable repository instructions, including `AGENTS.md`.
2. Inspect the worktree before staging:
   - Run `git status --short`.
   - Review `git diff --stat`, `git diff`, and `git diff --cached` as relevant.
   - Read recent messages with `git log --oneline -12`.
   - Run `git diff --check` before committing.
3. Establish scope before staging:
   - Honor an explicit file list or requested scope.
   - Keep unrelated modifications out of the commit.
   - Do not stage untracked files by default. Ask if their inclusion is unclear.
   - If the user asks only to commit current changes, stage the reviewed tracked modifications and deletions explicitly by path.
4. Draft the message from the repository's actual recent pattern:
   - Reuse the prevailing prefix and format, such as `feat:`, `fix:`, `update:`, or `chore:`.
   - Make the subject concise, specific, and aligned with the staged diff.
   - Prefer the user's wording if they provide a message.
5. Stage only the selected paths with `git add -- <paths>`, then inspect `git diff --cached` and commit with `git commit -m '<message>'`.
6. Verify with `git log -1 --oneline` and `git status --short`. Report the commit hash, message, included paths, and any intentionally remaining worktree files.

## Guardrails

- Stop and ask when the intended set of changes cannot be determined safely.
- Never use `git add -A`, `git commit --amend`, `git push`, `git reset`, or destructive cleanup unless the user explicitly requests it.
- Do not commit generated build artifacts, credentials, or unrelated configuration merely because they are present in the worktree.
- If a hook fails, preserve the worktree, report its output, and fix or bypass it only with user authorization.
