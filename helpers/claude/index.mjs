import { serve } from './bridge.mjs';
const server = await serve();
for (const signal of ['SIGTERM', 'SIGINT', 'SIGHUP']) process.once(signal, () => { server.close(); process.stdin.destroy(); process.exitCode = 0; });
