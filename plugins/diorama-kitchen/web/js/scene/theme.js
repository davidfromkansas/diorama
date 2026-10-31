// Which scene the page shows: the kitchen (default) or the office (`?scene=office`, or the last
// one picked with the scene button). Both run the same agents through the same stations; only the
// room, its furniture, its props, its sounds and its words differ.

const params = new URLSearchParams(location.search)
const remembered = (() => { try { return localStorage.getItem('dioramaScene') } catch { return null } })()
const asked = params.get('scene') ?? remembered

export const sceneKind = asked === 'office' ? 'office' : 'kitchen'
export const isOffice = sceneKind === 'office'

/** Opens the page again on the other scene, keeping the session. */
export function switchScene(kind) {
  try { localStorage.setItem('dioramaScene', kind) } catch {}
  const next = new URLSearchParams(location.search)
  next.set('scene', kind)
  location.search = next.toString()
}

/** The words the page uses for the place and the people in it. */
export const vocabulary = isOffice
  ? { place: 'office', Place: 'Office', icon: '🏢', person: 'teammate', people: 'teammates', demo: 'Demo office' }
  : { place: 'kitchen', Place: 'Kitchen', icon: '🍳', person: 'chef', people: 'chefs', demo: 'Demo kitchen' }
