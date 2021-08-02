import rod / rod_types

proc setFlag(s: var set[NodeFlags], f: NodeFlags, v: bool) {.inline.} =
  if v: s.incl(f) else: s.excl(f)

proc setNodeFlag(n: Node, f: NodeFlags, v: bool) {.inline.} =
  setFlag(n.mWorld.flags[n.mIndex], f, v)

proc flags(n: Node): set[NodeFlags] {.inline.} =
  n.mWorld.flags[n.mIndex]

proc isEnabled*(n: Node): bool {.inline.} = NodeFlags.enabled in n.flags
proc `isEnabled=`*(n: Node, flag: bool) {.inline.} =
  n.setNodeFlag(NodeFlags.enabled, flag)

proc affectsChildren*(n: Node): bool {.inline.} = NodeFlags.affectsChildren in n.flags
proc `affectsChildren=`*(n: Node, flag: bool) {.inline.} =
  n.setNodeFlag(NodeFlags.affectsChildren, flag)

proc isDirty*(n: Node): bool {.inline.} = NodeFlags.dirty in n.flags
proc `isDirty=`*(n: Node, flag: bool) {.inline.} =
  n.setNodeFlag(NodeFlags.dirty, flag)

proc isSerializable*(n: Node): bool {.inline.} = NodeFlags.serializable in n.flags
proc `isSerializable=`*(n: Node, flag: bool) {.inline.} =
  n.setNodeFlag(NodeFlags.serializable, flag)
