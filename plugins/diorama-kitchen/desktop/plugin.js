// Diorama Kitchen in Hermes Desktop: a Kitchen tab beside the chat that shows the focused chat's
// agents as chefs, live. Open it from the status bar's Kitchen button, ⌘K → "Open kitchen", or by
// typing /kitchen in a chat. The page itself comes from the kitchen's local server (started by
// the plugin's backend), shown in the app's sandboxed frame.

import { host, useValue, SandboxedFrame, PALETTE_AREA, STATUSBAR_AREAS } from '@hermes/plugin-sdk'
import { useEffect, useState } from 'react'
import { jsx, jsxs } from 'react/jsx-runtime'

const TAB = 'diorama-kitchen'

function KitchenView({ ctx, pinned }) {
  const stored = useValue(host.state.focusedStoredSessionId)
  const active = useValue(host.state.activeSessionId)
  const focused = stored ?? active
  // Clicking into the tab can take focus off the chat: keep showing the last chat it followed.
  const [session, setSession] = useState(pinned ?? focused ?? null)
  const [kitchen, setKitchen] = useState(null)
  useEffect(() => { if (focused) setSession(focused) }, [focused])
  useEffect(() => {
    let live = true
    setKitchen(null)
    ctx.rest(`/open?session=${encodeURIComponent(session ?? '')}`, { timeoutMs: 15000 })
      .then((result) => { if (live) setKitchen(result) })
      .catch((error) => { if (live) setKitchen({ ok: false, error: String(error?.message ?? error) }) })
    return () => { live = false }
  }, [session])

  if (!kitchen) return jsx('div', { className: 'flex h-full items-center justify-center text-sm text-(--ui-text-tertiary)', children: 'Opening the kitchen…' })
  if (!kitchen.ok) {
    return jsxs('div', {
      className: 'flex h-full flex-col items-center justify-center gap-2 p-6 text-center text-sm text-(--ui-text-secondary)',
      children: [
        jsx('div', { className: 'font-medium', children: 'The kitchen could not open' }),
        jsx('div', { className: 'text-(--ui-text-tertiary)', children: kitchen.error || 'Is the Diorama Kitchen plugin turned on in Settings → Plugins?' })
      ]
    })
  }
  return jsxs('div', {
    className: 'flex h-full flex-col',
    children: [
      jsx(SandboxedFrame, { src: kitchen.embed, title: 'Diorama Kitchen', className: 'min-h-0 w-full flex-1 border-0' }),
      jsx('div', {
        className: 'flex justify-end px-2 py-1 text-[0.6875rem] text-(--ui-text-tertiary)',
        children: jsx('button', { type: 'button', className: 'hover:text-(--ui-text-secondary)', onClick: () => void ctx.os.openExternal(kitchen.url), children: 'Open in browser' })
      })
    ]
  })
}

export default {
  id: 'diorama-kitchen',
  name: 'Diorama Kitchen',
  register(ctx) {
    let close = null
    const open = (pinned) => {
      if (typeof host.openWorkspace !== 'function') {
        host.notify({ kind: 'info', message: 'Update Hermes Desktop to show the kitchen in a tab. Opening it in your browser instead.' })
        ctx.rest(`/open?session=${encodeURIComponent(pinned ?? host.state.focusedStoredSessionId.get() ?? '')}`)
          .then((r) => r.ok ? ctx.os.openExternal(r.url) : host.notify({ kind: 'error', message: r.error }))
        return
      }
      close = host.openWorkspace(TAB, {
        title: 'Kitchen',
        dock: { pane: 'workspace', pos: 'right' },
        minWidth: '20rem',
        render: () => jsx(KitchenView, { ctx, pinned }),
        onClose: () => { close = null }
      })
    }
    ctx.onDispose(() => close?.())
    ctx.onEvent('plugin.diorama-kitchen.open', (event) => open(event?.payload?.session ?? null))
    ctx.registerMany([
      {
        id: 'open',
        area: PALETTE_AREA,
        data: { id: 'diorama-kitchen.open', label: 'Open kitchen', keywords: ['kitchen', 'diorama', 'agents', 'chefs'], run: () => open(null) }
      },
      {
        id: 'status',
        area: STATUSBAR_AREAS.right,
        order: 140,
        data: { id: 'diorama-kitchen', label: 'Kitchen', title: 'Watch this chat\'s agents in the kitchen', variant: 'action', toggleLabel: 'Kitchen', onSelect: () => open(null) }
      }
    ])
  }
}
