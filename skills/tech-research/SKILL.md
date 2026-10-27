---
name: tech-research
description: "Use when the user asks to add a dependency or pick a library, framework or tool, before a non-trivial integration (auth, payments, uploads, real-time), when filling a [FRAMEWORK]/[LIBRARY] placeholder, or before coding against an API you haven't verified recently. Produces a recommendation with alternatives, gotchas and doc links, saved to KNOWLEDGE.md."
---

# Technology Selection, Best Practices & Documentation Research

## Triggers — run this protocol automatically when:

- User asks to add a library, framework, or tool
- User asks to implement a non-trivial feature (auth, payments, file uploads, real-time, etc.)
- A placeholder `[framework]` or `[library]` is being filled during bootstrap
- You are about to write code for an integration you haven't verified recently

## Research protocol (execute in order)

1. **Search** for the current best options — check GitHub stars, last commit date, open issues,
   known CVEs, deprecation notices, and community adoption
2. **Fetch the official documentation** for the chosen technology — read the quickstart, API
   reference, and any "gotchas" or migration guides
3. **Search for best practices** — official style guides, security hardening docs, performance
   guides, and patterns recommended by the maintainers
4. **Check for known issues** — common pitfalls, breaking changes in recent versions, and
   unpatched CVEs

## Output format — always present to the user

- **Recommended option** with rationale (why this one)
- **Alternative** with pros/cons comparison
- **Key gotchas** discovered during research
- **Links** to the docs you read

## After research

- Save findings to `.github/KNOWLEDGE.md` under the relevant category
- Include: what was chosen, why, links to official docs, key patterns, and gotchas
- Commit: `git commit -m "docs(knowledge): add [technology] research and best practices"`

## Quality bar

- Never use a library with no commits in the last 12 months without flagging it
- Never use a library with a critical unpatched CVE without flagging it
- Prefer official/first-party over third-party when both solve the problem equally
- Always use the latest stable version unless the project has a documented reason not to
