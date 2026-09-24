---
name: git-commit-message
description: Generate a single-line Conventional Commit message from changes, matching this repository's recent git log style. Use when asked for a commit message or commit subject; leave staging, committing, and pushing to the user.
---

# Git Commit Message

Generate only the commit message. Use read-only inspection; never edit files, stage, commit, amend, push, or run builds and tests for this task.

## Inspect

- Read `git status --short` and `git log -8 --format=%s` in the target repository. If there is no history, use the standard format below.
- Honor an explicitly supplied diff or change scope. Otherwise, use `git diff --cached` when staged changes exist, excluding unstaged changes even in partially staged files. If nothing is staged, inspect `git diff` and relevant untracked files without staging them. Read the actual changes, not just filenames or diff statistics.
- If there are no changes or supplied details, do not invent a commit: return one short Indonesian line stating that no changes are available. If essential input is missing or inspection fails, return one short clarification or blocker instead.

## Compose

- Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/): `type(scope): description`, with an optional scope and `!` immediately before `:` for an evidenced breaking change. Describe the break in the subject since there is no body or footer.
- Use `feat` for new functionality, `fix` for bug fixes, or another appropriate type such as `docs`, `refactor`, `perf`, `test`, `build`, `ci`, or `chore`. Choose the type that represents the main change; do not copy an inaccurate type just to match history.
- Match the recent log's language, casing, scope usage, and description style where compatible with the specification. Default to concise English when history gives no useful pattern.
- If recent subjects consistently use `dev part N: ...`, preserve that description prefix and increment the latest applicable number. Derive it from the current log, never hardcode it. Ignore unrelated release or merge subjects when identifying this sequence.
- Summarize the main outcome of the selected changes in one concise subject. Do not invent features, successful checks, or changes outside the selected scope.

## Output

Return exactly one plain-text line containing the commit subject. No Markdown, code fences, quotes, labels, alternatives, explanation, body, footer, or shell command. Keep intermediate narration silent unless higher-priority instructions require it. The user performs every Git mutation manually.
