---
name: new-note
description: Scaffold a new KB note with proper structure and metadata
arguments: [topic, category]
---

## Create New KB Note

Create a new note for topic `$ARGUMENTS.topic` in category `$ARGUMENTS.category`.

### Categories and Paths

Map the category to the correct docs path:
- `note` or `notes` -> `docs/notes/`
- `guide` -> `docs/guides/`
- `article` -> `docs/articles/`
- `playbook` -> `docs/playbooks/`
- `blog` -> `docs/blog/posts/`

### Note Template

Use this structure for the new file:

```markdown
# <Title>

<One-line summary of what this note covers and why it matters.>

## Prerequisites

- List any required tools, access, or prior knowledge

## Context

Brief background on when and why you would use this.

## Steps

### Step 1: <action>

<description and commands>

### Step 2: <action>

<description and commands>

## Verification

How to confirm everything worked.

## Troubleshooting

Common issues and their solutions.

## References

- Links to official docs, related notes, or upstream issues
```

### After Creating

1. Generate a kebab-case filename from the topic
2. Write the file to the correct category path
3. Remind the user to add the new page to `mkdocs.yml` nav if they want it published
