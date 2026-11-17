/**
 * skills plugin for OpenCode.ai
 *
 * Two jobs, both of which OpenCode exposes as in-process hooks rather than a
 * session-start shell command:
 *
 *   1. `config` registers skills/ so OpenCode discovers the collection without
 *      symlinks or hand-edited config.
 *   2. `experimental.chat.messages.transform` injects the using-skills bootstrap
 *      into the first user message, so the agent knows skills exist at all.
 */

import path from 'path';
import fs from 'fs';
import os from 'os';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BOOTSTRAP_MARKER = 'skills:using-skills bootstrap for opencode';

const skillsDir = path.resolve(__dirname, '../../skills');
const bootstrapSkillPath = path.join(skillsDir, 'using-skills', 'SKILL.md');
const pluginJsonPath = path.resolve(__dirname, '../../.claude-plugin/plugin.json');

// Module-level cache. SKILL.md does not change mid-session, and the transform
// hook below fires on every agent step — not every turn — so re-reading from
// disk each time would be pure waste.
// undefined = not yet loaded, null = file missing.
let bootstrapCache;

const stripFrontmatter = (content) => {
  const match = content.match(/^---\n[\s\S]*?\n---\n([\s\S]*)$/);
  return (match ? match[1] : content).trim();
};

// The collection name is branding, and branding is the one thing a fork must
// change. Read it from plugin.json so a rename is a one-field edit, matching
// what hooks/session-start does for the shell-hook harnesses.
const readCollectionName = () => {
  try {
    const name = JSON.parse(fs.readFileSync(pluginJsonPath, 'utf8')).name;
    return /^[A-Za-z0-9._-]+$/.test(name) ? name : 'skills';
  } catch {
    return 'skills';
  }
};

const toolMapping = `## OpenCode tool mapping

Skills name actions, not tools. On OpenCode those actions resolve to:

- Invoke a skill → OpenCode's native \`skill\` tool
- Track tasks ("create a todo", "mark complete") → \`todowrite\`
- Dispatch a subagent → \`task\` with \`subagent_type: "general"\`, or \`"explore"\` for read-only codebase exploration
- Read a file → \`read\`
- Create, edit, or delete a file → \`apply_patch\`
- Run a shell command → \`bash\`
- Search file contents / find files by name → \`grep\`, \`glob\`
- Fetch a URL → \`webfetch\``;

const getBootstrapContent = () => {
  if (bootstrapCache !== undefined) return bootstrapCache;

  if (!fs.existsSync(bootstrapSkillPath)) {
    bootstrapCache = null;
    return null;
  }

  const body = stripFrontmatter(fs.readFileSync(bootstrapSkillPath, 'utf8'));

  bootstrapCache = `<EXTREMELY_IMPORTANT>
${BOOTSTRAP_MARKER}

You have ${readCollectionName()}.

The using-skills content below is ALREADY LOADED — you are following it now. Do
not call the skill tool to load using-skills again. Load any other skill on
demand with OpenCode's native skill tool.

${body}

${toolMapping}
</EXTREMELY_IMPORTANT>`;

  return bootstrapCache;
};

export const ObSkillsPlugin = async () => {
  return {
    // Push skills/ into the live config object. This works because Config.get()
    // returns a cached singleton, so a mutation here is visible when OpenCode
    // lazily discovers skills later.
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(skillsDir)) {
        config.skills.paths.push(skillsDir);
      }
    },

    // Inject into the first *user* message rather than a system message: system
    // messages get repeated every turn (token bloat), and more than one system
    // message breaks some models outright.
    'experimental.chat.messages.transform': async (_input, output) => {
      const bootstrap = getBootstrapContent();
      if (!bootstrap || !output.messages.length) return;

      const firstUser = output.messages.find((m) => m.info.role === 'user');
      if (!firstUser || !firstUser.parts.length) return;

      // OpenCode reloads messages from the DB on each agent step and can pass an
      // already-transformed array back through this hook. Without this guard the
      // bootstrap stacks up copy after copy.
      const alreadyInjected = firstUser.parts.some(
        (p) => p.type === 'text' && typeof p.text === 'string' && p.text.includes(BOOTSTRAP_MARKER),
      );
      if (alreadyInjected) return;

      const ref = firstUser.parts[0];
      firstUser.parts.unshift({ ...ref, type: 'text', text: bootstrap });
    },
  };
};

export default ObSkillsPlugin;
