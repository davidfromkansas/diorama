// A scripted session for trying the page without Claude Code (?demo): a main agent and a few
// subagents moving through the kitchen's stations. `?demo=still` shows one busy moment, unmoving.

const base = {
  isMain: false, status: 'working', attentionReason: null, freshness: 'live', latestTool: '', latestToolDetail: '', turnHasEdits: false,
  feed: [], plan: null, planProgress: null, latestRequest: null, model: 'claude-opus-5-5', modelLabel: 'Opus 5.5',
}
const work = (extra = {}) => ({ files: [], commands: 0, failedCommands: 0, tests: [], resources: [], ...extra })

function make(id, name, fields, now, started) {
  const feed = [{ kind: 'started', title: 'Turn started', time: started }, ...(fields.steps ?? []).map((title, i) => ({ kind: 'tool', title, outcome: 'done', time: started + i * 1000 }))]
  if (fields.current) feed.push({ kind: 'tool', title: fields.current, outcome: 'running', time: now })
  return {
    ...base, id, name, task: fields.task, title: fields.title, isMain: id === 'main', agentType: fields.agentType,
    completionKey: `demo:${id}:${fields.turn ?? 1}`, meaningfulEventID: `${id}:${fields.status ?? 'working'}:${fields.latestTool ?? ''}`,
    meaningfulUpdatedAt: now, observedAt: now, lastToolAt: now, lastCommentaryAt: now, startedAt: started,
    turnWork: work(fields.work), feed, ...fields,
  }
}

const plan = (done, total, titles) => ({
  checklist: titles.slice(0, total).map((title, i) => ({ title, status: i < done ? 'completed' : i === done ? 'in_progress' : 'pending' })),
  tasksPreviousTurn: false, completedTaskCount: done,
})
const steps = ['Read the kitchen scene', 'Port the chef director', 'Wire the live server', 'Add the plugin command', 'Test end to end']

/** Each beat: seconds from the start, and what every agent is doing from then on. */
function beats() {
  const main = { task: 'Build a live kitchen view for Claude Code sessions', title: 'Live Kitchen View' }
  return [
    [0, { main: { ...main, latestTool: 'Read', latestToolDetail: '/src/scene/kitchen.swift', current: 'Read kitchen.swift' } }],
    [7, { main: { ...main, latestTool: 'TodoWrite', current: 'Plan 5 steps', plan: plan(0, 5, steps), planProgress: { kind: 'steps', done: 0, total: 5 } } }],
    [13, {
      main: { ...main, latestTool: 'Edit', latestToolDetail: '/web/js/scene/kitchen.js', turnHasEdits: true, current: 'Edit kitchen.js', plan: plan(1, 5, steps), planProgress: { kind: 'steps', done: 1, total: 5 }, work: { files: ['/web/js/scene/kitchen.js'] } },
      iris: { task: 'Find how hooks report subagents', title: 'Find Hook Events', agentType: 'Explore', latestTool: 'Grep', latestToolDetail: 'SubagentStart', current: 'Search for SubagentStart' },
    }],
    [21, {
      main: { ...main, latestTool: 'Bash', latestToolDetail: 'npm run build', turnHasEdits: true, current: 'Run npm run build', plan: plan(2, 5, steps), planProgress: { kind: 'steps', done: 2, total: 5 }, work: { files: ['/web/js/scene/kitchen.js', '/server/server.mjs'], commands: 1 } },
      iris: { task: 'Find how hooks report subagents', title: 'Find Hook Events', agentType: 'Explore', latestTool: 'Read', latestToolDetail: '/docs/hooks.md', current: 'Read hooks.md' },
      otto: { task: 'Run the test suite and report failures', title: 'Run Test Suite', agentType: 'general-purpose', latestTool: 'Bash', latestToolDetail: 'npm test', current: 'Run npm test', work: { tests: [{ command: 'npm test', outcome: 'running' }] } },
    }],
    [30, {
      main: { ...main, status: 'waiting', attentionReason: 'approval', latestTool: 'Bash', latestToolDetail: 'git push', turnHasEdits: true, plan: plan(3, 5, steps), planProgress: { kind: 'steps', done: 3, total: 5 }, work: { files: ['/web/js/scene/kitchen.js', '/server/server.mjs'] } },
      iris: { task: 'Find how hooks report subagents', title: 'Find Hook Events', agentType: 'Explore', status: 'done', freshness: 'recentlyObserved' },
      otto: { task: 'Run the test suite and report failures', title: 'Run Test Suite', agentType: 'general-purpose', latestTool: 'Skill', latestToolDetail: 'webapp-testing', current: 'Use webapp-testing', work: { tests: [{ command: 'npm test', outcome: 'passed' }], resources: ['webapp-testing'] } },
    }],
    [44, {
      main: { ...main, latestTool: 'Edit', latestToolDetail: '/web/css/kitchen.css', turnHasEdits: true, current: 'Edit kitchen.css', plan: plan(4, 5, steps), planProgress: { kind: 'steps', done: 4, total: 5 }, work: { files: ['/web/js/scene/kitchen.js', '/server/server.mjs', '/web/css/kitchen.css'] } },
      iris: { task: 'Find how hooks report subagents', title: 'Find Hook Events', agentType: 'Explore', status: 'done', freshness: 'lastKnown' },
      otto: { task: 'Run the test suite and report failures', title: 'Run Test Suite', agentType: 'general-purpose', status: 'done', freshness: 'recentlyObserved' },
    }],
    [54, {
      main: { ...main, status: 'done', turnHasEdits: true, plan: plan(5, 5, steps), planProgress: { kind: 'steps', done: 5, total: 5 }, work: { files: ['/web/js/scene/kitchen.js', '/server/server.mjs', '/web/css/kitchen.css'] } },
      iris: { task: 'Find how hooks report subagents', title: 'Find Hook Events', agentType: 'Explore', status: 'done', freshness: 'lastKnown' },
      otto: { task: 'Run the test suite and report failures', title: 'Run Test Suite', agentType: 'general-purpose', status: 'done', freshness: 'lastKnown' },
    }],
  ]
}
const names = { main: 'Milo', iris: 'Iris', otto: 'Otto' }

/** Plays the script on `clock` (seconds); returns a tick to call every frame. */
export function demoAgents(show, mode, clock) {
  const script = beats(), wall = () => Date.now() + (clock() - performance.now() / 1000) * 1000
  let start = clock(), index = -1
  const at = (i) => {
    const [, cast] = script[i], now = wall()
    return Object.entries(cast).map(([id, fields]) => make(id, names[id], fields, now, now - (clock() - start - script[i][0]) * 1000))
  }
  if (mode === 'still') { show(at(3)); return () => {} }
  return () => {
    const t = clock() - start
    if (index + 1 < script.length && t >= script[index + 1][0]) { index += 1; show(at(index)) }
    else if (index === script.length - 1 && t > script[index][0] + 25) { start = clock(); index = -1 }
  }
}
