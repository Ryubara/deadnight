# Lessons

Problems we hit building Deadnight and how we solved them. Before solving something, search these pages: it may have
happened before. What holds for any game goes into the section of the kit's
[topic pages](https://ryubara.github.io/gdstudio/studio/rules/) it belongs to, in a kit pull request; the kit keeps no
lessons of its own (gdstudio #770).

## Adding a lesson

One problem per file: `docs/lessons/<yyyy-mm-dd>-<slug>.md`, where the slug is a few words of the problem in
lowercase with hyphens. The navigation lists every file in this folder by itself, so adding a lesson never touches a
shared file and never conflicts with another pull request.

```markdown
# Short statement of the problem

2026-11-01

- **Symptom:** what you observed, with the exact error text if there is one.
- **Cause:** why it happened.
- **Fix:** what solved it.
- **Documented:** [the page that now covers it](../research/index.md).
```
