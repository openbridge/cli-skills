# Third-Party Notices

This project includes material adapted from third-party open-source projects.
Their license notices are reproduced below as required.

---

## obra/superpowers

- **Source:** https://github.com/obra/superpowers
- **License:** MIT
- **Copyright:** © 2025 Jesse Vincent
- **Adapted from version:** 6.3.0

### What was adapted

The multi-harness packaging approach and the harness adapters are derived from
that project. Specifically:

| File in this repository | Derived from |
|---|---|
| `hooks/session-start` | `hooks/session-start` — the per-harness JSON output branching, the `jq`-free bash JSON escaper, and the `printf`-instead-of-heredoc workaround |
| `hooks/run-hook.cmd` | `hooks/run-hook.cmd` — the polyglot cmd/bash wrapper and its extensionless-filename convention |
| `hooks/hooks.json`, `hooks/hooks-cursor.json` | the corresponding hook configurations |
| `.opencode/plugins/skills.js` | `.opencode/plugins/superpowers.js` |
| `.opencode/INSTALL.md` | `.opencode/INSTALL.md` |
| `.pi/extensions/skills.ts` | `.pi/extensions/superpowers.ts` |
| `.hermes-plugin/__init__.py`, `.hermes-plugin/plugin.yaml` | `.hermes-plugin/__init__.py`, `.hermes-plugin/plugin.yaml` |
| `gemini-extension.json`, `GEMINI.md` | the corresponding Gemini CLI extension files |
| `skills/using-skills/references/*-tools.md` | `skills/using-superpowers/references/*-tools.md` |
| `package.json` (`main`, `pi` fields) | the corresponding declarations |
| Plugin manifests under `.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`, `.devin-plugin/`, `.kimi-plugin/`, `.agents/` | the corresponding manifests |
| `docs/harness-support-matrix.md` | analysis of that project's `docs/porting-to-a-new-harness.md` and its reference integrations |

Identity fields (name, author, homepage, repository, keywords, description),
skill names, and cross-references to skills this collection does not contain
were rewritten rather than copied. The skills in `skills/` are original to this
project.

### License text

```
MIT License

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Not covered

The name "Superpowers" and that project's branding are not licensed by the MIT
grant. Nothing in this repository uses them.
