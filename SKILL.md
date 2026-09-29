---
name: install-update-instructions
description: Install or update the always-on global instruction files bundled with this skill (instructions.md engineering rules and instructions_personal.md domain rules) for the coding agent in use. Claude Code gets ~/.claude/instructions plus a managed loader block in ~/.claude/CLAUDE.md; Codex, Gemini CLI, OpenCode, or any tool that reads a markdown rules file get a managed block in their global rules file. Use it when the user says "install the instructions", "update the instructions", "install this instructions package", "check if my instructions changed", or points you at an install-update-instructions tarball or directory. Never run it on your own initiative.
compatibility: bash 4+, awk, diff, cmp, tar. Works with Claude Code, Codex, Gemini CLI, OpenCode, and any agent that reads a markdown rules file.
---

# Install / Update Global Instructions

This skill is self-contained. The instruction files live inside the skill under `instructions/`,
so nothing outside the skill directory is needed. The installer copies them into a per-user
location and writes a **managed block** (between `<!-- BEGIN global-instructions ... -->` and
`<!-- END global-instructions -->`) into the agent's global rules file. On later runs the block is
replaced in place; other content in that file is never touched. The installer is the only
sanctioned way the installed copies change.

## Step 0: plan mode first, then git (mandatory, before anything else)

1. **Enter your plan mode now**, before running any command (Claude Code: call `EnterPlanMode`;
   other agents: their plan / read-only mode, if they have one). If plan mode is declined, stop and
   ask the user how to proceed. If a different plan is already in the session's plan view, first save
   it to its project's `PLAN.md` and tell the user the plan view will switch.
2. **Git check (read-only).** The *working folder* is the session's current working directory
   (`pwd` when the session started, the project the user is working in). It is **never** the agent's
   config directory (`~/.claude` or `$CLAUDE_CONFIG_DIR`, `~/.agents`, `~/.codex`, `~/.gemini`,
   `~/.config/opencode`), this skill's own directory, or the install target. In the working folder run
   `git -C "$PWD" rev-parse --is-inside-work-tree`.
   - Already a repo (or inside one): use it and do not re-initialize.
   - Not a repo: put "git init + initial commit of <listed files>" in the plan as an **optional**
     step the user can accept or decline. Never initialize `$HOME`, `/`, or any agent config
     directory; if the working folder is one of those, skip git and say so. If the folder holds more
     than about 10,000 files, ask first.
   - git not installed: say so, suggest installing it, and continue without git.
   - Local only: no remotes, no push unless the user asks, never change global git config. If no
     identity is set, ask for a name and email and use `git config --local`.
3. **Dry run (read-only):** the installer with `--check` (commands below). Read the diff it prints.
4. **Write the plan** with a todo list: files that will be installed / updated / unchanged, a short
   summary of each diff, the loader action, the git steps (working folder only), and the **exact
   commit message(s)**. Make the plan visible to the user (Claude Code: an Artifact page when
   available).
5. **Get approval** (Claude Code: `ExitPlanMode`). Approving the plan approves the commit messages.
   Nothing is installed before approval. The installer writes only into agent config directories;
   those files are **not** committed (never put an agent config directory under git). To revert an
   install, use the diff the installer printed and the copy in `<skills dir>_backup/`. Commit in the
   working folder only when this session changed files there (e.g. edited source `*.md` and rebuilt
   the bundle), staging specific files only (never `git add .`, never data files), and include the
   commit hash in the report. If nothing changed there, report "no commit: install touched only the
   agent config directory".

## When the user hands you a package (tarball or directory)

```bash
tar xzf install-update-instructions-<version>.tar.gz     # skip if you were given a directory
./install-update-instructions/install.sh --check          # dry run for Claude Code
./install-update-instructions/install.sh                  # install for Claude Code
./install-update-instructions/install.sh --agent codex    # or: gemini | opencode | all | file --file PATH
```

Pick the `--agent` value for the agent you are (Claude Code needs none). `all` installs for every
agent whose config directory already exists (`~/.codex`, `~/.gemini`, `~/.config/opencode`).

What `install.sh` does:
- Claude Code: copies the skill to `~/.claude/skills/install-update-instructions/`, installs the
  files to `~/.claude/instructions/`, writes the managed block (with `@instructions/...` imports)
  into `~/.claude/CLAUDE.md`, migrating the older unmarked block if present.
- Other agents: copies the skill to `~/.agents/skills/install-update-instructions/` (the user-level
  skills directory Codex scans), installs the files to `~/.agents/instructions/`, then writes the
  managed block into the agent's global rules file:

  | agent | rules file | block content |
  |---|---|---|
  | codex | `~/.codex/AGENTS.md` | files inlined (Codex has no import syntax) |
  | gemini | `~/.gemini/GEMINI.md` | `@/abs/path` imports of the installed files |
  | opencode | `~/.config/opencode/AGENTS.md` | files inlined |
  | file `--file PATH` | PATH | files inlined |
  | print | stdout | block to paste into a UI-based tool |

  Codex caps combined AGENTS.md content at `project_doc_max_bytes` (32 KiB default); the installer
  warns when the inlined block exceeds it. Fix: `project_doc_max_bytes = 65536` in
  `~/.codex/config.toml`, or `--exclude instructions_personal.md`.

A previous copy of the skill is moved to `<skills dir>_backup/` before the new one is copied.
Paths honor `CLAUDE_CONFIG_DIR`, `AGENTS_HOME`, `CODEX_HOME`, `GEMINI_HOME`, `XDG_CONFIG_HOME`.

## When the skill is already installed

1. Dry run first if the user only asks whether anything changed:
   ```bash
   <skill dir>/scripts/install_update.sh --check                 # Claude Code
   <skill dir>/scripts/install_agents.sh --agent <name> --check  # other agents
   ```
2. Install or update by running the same command without `--check`. Options: `--exclude FILE`
   (skip a bundled file, e.g. `instructions_personal.md`), `--version` (Claude installer).
   The installer prints a unified diff (local → bundle) for every changed file and a summary
   line: installed / updated / unchanged files and the loader action.
3. Report to the user in plain language: which files were installed, updated, or unchanged, and
   what the diffs changed (which sections or rules). Paste short diffs in a code block; summarize
   long ones.
4. Remind the user that the updated rules apply from the next new session, not the current one.

## Maintainer: refreshing the bundle

The owner of the instruction text edits the files, then rebuilds the bundle and the tarball:

```bash
<skill dir>/scripts/build_bundle.sh --from <dir with the edited *.md>     # add --check to preview
```

This copies `*.md` into the bundle (showing diffs), writes `VERSION` and `MANIFEST.sha256`, and
produces `install-update-instructions-<version>.tar.gz` in `<skill dir>/../../dist` (override with
`--out DIR`). Share that tarball, or the skill directory itself.

## Rules

- Step 0 always comes first; there are no exceptions for "small" updates.
- Do not edit the installed copies by hand; go through the installer.
- Do not edit inside the managed block; the installer owns it.
- Do not run the installer or the bundle refresh unless the user asked for it in this session.
