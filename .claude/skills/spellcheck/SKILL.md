---
name: spellcheck
description: Check spelling and grammar in markdown files
allowed-tools: Read Bash(find *) Bash(grep *)
arguments: [path]
---

## Spell and Grammar Check

Check the file or directory at `$ARGUMENTS.path` for spelling and grammar issues.

### Scope

- If `path` is a file, check that single file
- If `path` is a directory, find all `*.md` files and check each

### What to Check

1. **Spelling errors** in prose (skip code blocks, URLs, and technical terms)
2. **Grammar issues** (subject-verb agreement, tense consistency, sentence fragments)
3. **Technical term consistency** (e.g., "OpenShift" not "openshift" in prose, "Kubernetes" not "kubernetes")
4. **Common markdown issues** (broken links syntax, unclosed code fences, inconsistent header levels)

### Known Technical Terms (do not flag)

OpenShift, Kubernetes, kubectl, oc, AWS, Azure, GCP, NLB, ALB, ELB, VPC, CIDR, STS, OIDC, IAM, EC2, S3, EBS, CCO, CVO, etcd, CoreDNS, OVN, SDN, MTU, MCP, RHEL, RHCOS, SNO, HCP, ROSA, OCI, CAPI, CAPZ

### Output Format

For each file with issues:
```
## <filepath>
- Line <N>: "<wrong>" -> "<suggested>" (spelling|grammar|consistency)
```

End with a summary count of issues found.
