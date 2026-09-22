// Read-only SDK helpers: do not instantiate query or resume a session.
import { getSubagentMessages, listSubagents } from '@anthropic-ai/claude-agent-sdk';
import { historyPreview } from './history-format.mjs';
const [sessionId, childId, dir] = process.argv.slice(2);
if (!sessionId || !childId || !dir) throw Error('Missing history identity');
const ids = await listSubagents(sessionId, { dir });
if (!ids.includes(childId)) throw Error('Child history unavailable for this parent');
const messages = await getSubagentMessages(sessionId, childId, { dir, limit: 300 });
process.stdout.write(JSON.stringify(historyPreview(messages)));
