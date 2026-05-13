# CLAUDE.md - mtulio's Labs KB

Personal knowledge base repository: technical notes, guides, articles, and lab playbooks.
Published via MkDocs Material to https://mtulio.dev.

## Project Structure

```
docs/           # All content lives here
  articles/     # Polished articles (published)
  blog/posts/   # Blog entries (MkDocs blog plugin)
  guides/       # Step-by-step guides and labs
  notes/        # Quick notes and drafts
  playbooks/    # Runbook-style operational playbooks
labs/           # Hands-on lab code and tooling
hack/           # Helper scripts
api/            # Serverless MCP experiments
mkdocs.yml      # Site config and navigation
Makefile        # Build targets (venv, mkdocs-serve, mkdocs-build)
```

## Build and Serve

```bash
make requirements    # Install Python deps into .venv
make mkdocs-serve    # Local dev server at 127.0.0.1:8080
make mkdocs-build    # Build static site
```

## Content Conventions

- **Language**: English
- **Format**: Markdown with MkDocs Material extensions (admonitions, tabs, mermaid, code highlighting)
- **File naming**: kebab-case, prefixed by product/topic (e.g., `ocp-aws-local-zones-day-2.md`)
- **Navigation**: New pages must be added to `mkdocs.yml` `nav:` section to appear on the site
- **Code blocks**: Always use fenced blocks with language tags (```bash, ```yaml, etc.)
- **Structure for guides**: Context > Prerequisites > Steps > Verification > Troubleshooting > References

## Commit Style

Conventional commits: `type(scope): description`

Common types and scopes:
- `docs(notes)`: Quick notes and drafts
- `docs(guides)`: Step-by-step guides
- `docs(articles)`: Published articles
- `docs(blog)`: Blog posts
- `feat(labs)`: New lab tooling or experiments
- `build(deps)`: Dependency bumps
- `fix(docs)`: Corrections to existing content

Keep commit messages concise. The first line should be under 72 characters.

## Working with Content

- Prefer editing existing notes over creating new ones when the topic overlaps
- Draft/WIP content uses `.idea_` or `.todo_` filename prefixes in `docs/articles/`
- Notes in `docs/notes/` are informal; guides in `docs/guides/` should be copy-paste ready
- Articles in `docs/articles/` are publication-quality and should be reviewed before committing
- Technical terms: use proper casing in prose (OpenShift, Kubernetes, AWS) but lowercase in filenames

## AI Assistant Guidelines

- Review content for English spelling, grammar, and technical accuracy
- When creating notes, follow the structure in `.claude/skills/new-note/`
- When reviewing content, use criteria from `.claude/skills/review-note/`
- Do not modify `mkdocs.yml` nav without asking; adding an entry makes it public
- Default branch is `devel`; all work happens here
