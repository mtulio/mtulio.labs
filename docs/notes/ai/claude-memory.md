# Claude Code: Memory, Skills, and Settings

How to manage persistent context, custom commands, and configuration in Claude Code projects.

## Memory: Two Systems

### CLAUDE.md (you write, team shares)

Persistent instructions loaded at the start of every session. Placed in the repo and committed to git.

| File | Shared via git? | Purpose |
|------|----------------|---------|
| `CLAUDE.md` (repo root) | Yes | Team conventions, build commands, architecture |
| `.claude/CLAUDE.md` | Yes | Same, alternative location |
| `CLAUDE.local.md` | No (gitignore) | Personal overrides for this project |
| `~/.claude/CLAUDE.md` | No | Global instructions across all projects |

Keep under 200 lines. For larger guidance, use path-scoped rules.

#### Path-Scoped Rules

For large projects, split instructions into `.claude/rules/`:

```
.claude/rules/
├── testing.md
├── api-design.md
└── frontend/react.md
```

Scope rules to specific files with frontmatter:

```yaml
---
paths:
  - "src/api/**/*.go"
---
# API-specific rules here...
```

Rules only load when Claude reads matching files.

#### Importing Files

Reference external files in CLAUDE.md with `@path` syntax:

```markdown
See @README.md for overview and @package.json for available commands.
```

### Auto Memory (Claude learns, personal only)

Claude automatically saves observations (debugging patterns, preferences, project context) to:

- **User-level**: `~/.claude/memory/` — available in all projects
- **Project-level**: `~/.claude/projects/<encoded-path>/memory/` — scoped to one working directory

Structure:

- `MEMORY.md` — index file with one-line pointers (first 200 lines loaded automatically)
- Individual `.md` files — actual memory content with frontmatter (name, description, type)

Memory types: `user`, `feedback`, `project`, `reference`.

Commands:

- `/memory` — browse and manage memory files
- "remember that..." — ask Claude to save something
- "forget about..." — ask Claude to remove a memory
- "save to user memory" / "save to project memory" — control scope

## Skills (Custom Commands)

Reusable workflows invoked with `/<skill-name>`. Committed to git for team sharing.

### Creating a Skill

Create `.claude/skills/<name>/SKILL.md`:

```yaml
---
name: commit-checklist
description: Review changes before committing
disable-model-invocation: true
---

## Pre-commit Checklist

1. Run tests: `npm test`
2. Lint code: `npm run lint`
3. Check diff: `git diff --stat`
```

### Skill Frontmatter Options

```yaml
---
name: my-skill
description: What this does
disable-model-invocation: true   # Only user invokes (not Claude auto)
user-invocable: false            # Only Claude uses (hidden from menu)
allowed-tools: Bash(npm *) Read(src/**)
context: fork                    # Run in isolated subagent
agent: Explore                   # Which subagent type
arguments: [issue, branch]       # Named arguments
---
```

### Dynamic Context Injection

Skills can execute commands before Claude reads them:

```markdown
Diff: !`gh pr diff`
Comments: !`gh pr view --comments`

Summarize the changes above.
```

### Skill Locations

| Location | Scope | Shared? |
|----------|-------|---------|
| `~/.claude/skills/<name>/` | Personal | All your projects |
| `.claude/skills/<name>/` | Project | Team (commit to git) |

## Settings

### File Hierarchy (highest to lowest priority)

| File | Shared? | Purpose |
|------|---------|---------|
| Managed policy (`/etc/claude-code/`) | Org-wide | IT-enforced rules |
| `.claude/settings.local.json` | No (gitignore) | Personal overrides |
| `.claude/settings.json` | Yes (commit) | Team config |
| `~/.claude/settings.json` | No | Global personal preferences |

### Example `.claude/settings.json`

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": ["Bash(npm *)", "Read(src/**)", "Bash(git *)"],
    "deny": ["Read(.env*)", "Bash(rm *)"]
  },
  "env": {
    "NODE_ENV": "development"
  },
  "autoMemoryEnabled": true
}
```

## What to Commit vs. Gitignore

**Commit:**

- `CLAUDE.md` — team instructions
- `.claude/rules/` — path-scoped rules
- `.claude/skills/` — custom commands
- `.claude/settings.json` — team permissions and config

**Gitignore:**

```gitignore
CLAUDE.local.md
.claude/settings.local.json
```

## Quick Start for Any Repo

1. Run `/init` to auto-generate a starting `CLAUDE.md`
2. Edit it with conventions, build commands, architecture
3. Add `.claude/skills/` for repeatable workflows
4. Add `.claude/settings.json` for team tool permissions
5. Commit all of the above

## Repo File Structure Reference

```
your-repo/
├── CLAUDE.md                        # Project instructions (commit)
├── .claude/
│   ├── CLAUDE.md                    # Alternative location (commit)
│   ├── settings.json                # Team config (commit)
│   ├── settings.local.json          # Personal overrides (gitignore)
│   ├── rules/                       # Path-scoped rules (commit)
│   │   ├── testing.md
│   │   └── api-design.md
│   └── skills/                      # Custom commands (commit)
│       ├── review-checklist/
│       │   └── SKILL.md
│       └── deploy/
│           └── SKILL.md
```

User-level (not committed, machine-local):

```
~/.claude/
├── CLAUDE.md                        # Global personal instructions
├── settings.json                    # Global personal preferences
├── memory/                          # Auto memory (all projects)
│   ├── MEMORY.md
│   └── *.md
├── skills/                          # Personal custom commands
└── projects/<encoded-path>/memory/  # Project-scoped auto memory
```
