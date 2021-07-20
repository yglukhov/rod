import rod / rod_types

template setNodeFlag(n: Node, f: NodeFlags, v: bool) =
    if v: n.mFlags.incl(f) else: n.mFlags.excl(f)

proc isEnabled*(n: Node): bool {.inline.} = NodeFlags.enabled in n.mFlags
proc `isEnabled=`*(n: Node, flag: bool) {.inline.} =
    n.setNodeFlag(NodeFlags.enabled, flag)

proc affectsChildren*(n: Node): bool {.inline.} = NodeFlags.affectsChildren in n.mFlags
proc `affectsChildren=`*(n: Node, flag: bool) {.inline.} =
    n.setNodeFlag(NodeFlags.affectsChildren, flag)

proc isDirty*(n: Node): bool {.inline.} = NodeFlags.dirty in n.mFlags
proc `isDirty=`*(n: Node, flag: bool) {.inline.} =
    n.setNodeFlag(NodeFlags.dirty, flag)

proc isSerializable*(n: Node): bool {.inline.} = NodeFlags.serializable in n.mFlags
proc `isSerializable=`*(n: Node, flag: bool) {.inline.} =
    n.setNodeFlag(NodeFlags.serializable, flag)
