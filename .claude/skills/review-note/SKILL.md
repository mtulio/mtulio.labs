---
name: review-note
description: Review a KB note or guide for quality, clarity, and completeness
allowed-tools: Read Bash(grep *) Bash(wc *) Bash(find *)
arguments: [path]
---

## Review KB Note

Review the note at `$ARGUMENTS.path` for the following criteria:

### Content Quality
1. **Clarity**: Is the content clear and easy to follow?
2. **Completeness**: Are steps complete? Are there missing prerequisites or assumptions?
3. **Accuracy**: Do commands and configurations look correct?
4. **Structure**: Does it follow a logical flow (context, prerequisites, steps, verification, troubleshooting)?

### Writing Quality
1. **Grammar and spelling**: Flag any errors
2. **Consistency**: Consistent use of terminology, formatting, and voice
3. **Code blocks**: Are they properly fenced with language tags?
4. **Links**: Are references and links present where needed?

### Actionability
1. **Copy-paste ready**: Can a reader follow the guide end-to-end?
2. **Environment assumptions**: Are environment variables and prerequisites clearly stated?
3. **Verification steps**: Does each major step include a way to verify success?

Provide a summary with:
- Overall quality rating (draft / needs-work / good / polished)
- Top 3 issues to fix
- Suggested improvements (if any)
