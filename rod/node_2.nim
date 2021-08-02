import rod / [ rod_types, node_flags ]
import sequtils

proc setDirty*(n: Node)

const InvalidNodeIndex* = high(NodeIndex)

proc addNode(w: World, n: Node): NodeIndex =
  result = w.nodes.len.NodeIndex
  w.nodes.add(n)
  w.isDirty = true

proc getNode(w: World, i: NodeIndex): Node =
  if i < w.nodes.len.NodeIndex:
    return w.nodes[i]


proc dump*(w: World, prefix: string = "") =
  for i, n in w.nodes:
    if n.isNil:
      echo "[", prefix, ":", i, "]: nil"
      continue
    echo "[", prefix, ":", i, "]: ", n.mIndex, " : ", n.name, " [par ", n.mParent, ", fst ", n.mFirstChild, ", prv ", n.mPrev, ", nxt ", n.mNext, "]"

proc parent*(n: Node): Node

proc world*(n: Node): World =
  if not n.mWorld.isNil:
    return n.mWorld
  n.mWorld = new(World)
  n.mWorld.isDirty = true
  n.mIndex = n.mWorld.addNode(n)
  result = n.mWorld

proc first*(n: Node): Node =
  return n.world.getNode(n.mFirstChild)

proc next(n: Node): Node =
  return n.world.getNode(n.mNext)

proc `next=`(n: Node, nn: Node) =
  if nn.isNil:
    n.mNext = InvalidNodeIndex
    return
  n.mNext = nn.mIndex
  nn.mPrev = n.mIndex

proc prev(n: Node): Node =
  return n.world.getNode(n.mPrev)

proc parent*(n: Node): Node =
  return n.world.getNode(n.mParent)

proc `parent=`*(n: Node, p: Node) =
  if p.isNil:
    # echo n.name, " parent= nil"
    n.mParent = InvalidNodeIndex
  else:
    # echo n.name, " parent= ", p.name, " index ", p.mIndex
    n.mParent = p.mIndex
  n.setDirty()

proc last*(n: Node): Node =
  result = n.first
  if result.isNil: return
  while not result.next.isNil:
    result = result.next

type NodeChildrenIteratorProxy = distinct Node

proc children*(n: Node): NodeChildrenIteratorProxy = NodeChildrenIteratorProxy(n)

iterator items*(p: NodeChildrenIteratorProxy): Node =
  let n = p.Node
  var el = n.first
  var iters = 0
  while not el.isNil:
    yield el
    el = el.next
    if iters > n.world.nodes.len:
      raise newException(Exception, "looped ")
    inc iters

iterator pairs*(p: NodeChildrenIteratorProxy): (int, Node) =
  let n = p.Node
  var el = n.first
  var iters = 0
  while not el.isNil:
    yield (iters, el)
    el = el.next
    if iters > n.world.nodes.len:
      raise newException(Exception, "looped ")
    inc iters

proc len*(p: NodeChildrenIteratorProxy): int =
  for i, ch in p:
    inc result

proc `[]`*(p: NodeChildrenIteratorProxy, i: int): Node =
  for q, ch in p:
    if q == i: return ch

proc `[]`*(p: NodeChildrenIteratorProxy, i: BackwardsIndex): Node =
  let len = p.len
  for q, ch in p:
    if len - q == int(i): return ch

proc getSeq*(p: NodeChildrenIteratorProxy): seq[Node] =
  for ch in p:
    result.add(ch)

proc hasChildren*(n: Node): bool =
  n.mFirstChild != InvalidNodeIndex

proc seqOfChildren*(n: Node): seq[Node] =
  for ch in n.children:
    result.add(ch)

proc indexOf*(n: Node, c: Node): int =
  for ch in n.children:
    if ch == c: return
    inc result
  result = -1

proc childAt*(n: Node, i: int): Node =
  var q = 0
  for ch in n.children:
    if q == i: return ch
    inc q

proc childrenLen*(n: Node): int =
  for ch in n.children:
    inc result

proc printTree(n: Node, ident: string = "") =
  if n.isNil: return
  if ident.len == 0:
    echo "\nTREE"
  echo ident, n.mIndex, " : ", n.name
  for ch in n.children:
    ch.printTree(ident & "  ")

proc setDirty*(n: Node) =
  if not n.isDirty:
    n.isDirty = true
    for c in n.children:
      c.setDirty()

proc getOrder*(node: Node, order: var seq[NodeIndex]) =
  order.add(node.mIndex)
  # echo "getOrder ", node.name
  for ch in node.children:
    getOrder(ch, order)

proc getOrder*(node: Node): seq[NodeIndex] =
  node.getOrder(result)

proc setWorld(n: Node, w: World) =
  n.mWorld = w
  for ch in n.children:
    ch.setWorld(w)

proc moveToWorld(n: Node, w: World) =
  if n.mWorld.isNil:
    n.mIndex = w.addNode(n)
    n.setWorld(w)
    w.isDirty = true
    return

  if n.mWorld == w:
    w.isDirty = true
  w.isDirty = true
  let oldWorld = n.mWorld
  oldWorld.isDirty = true
  var indexes: seq[NodeIndex]

  # oldWorld.dump("before ")

  getOrder(n, indexes)
  # echo "indexes ", indexes

  for idx in indexes:
    let node = oldWorld.nodes[idx]
    let newIndex = w.addNode(node)
    node.mIndex = newIndex

  template offset(world: World, v: var NodeIndex) =
    if v != InvalidNodeIndex:
      # echo "offset ", v, " world ", world.nodes.len
      v = world.nodes[v].mIndex

  for oldIndex in indexes:
    oldWorld.offset(oldWorld.nodes[oldIndex].mParent)
    oldWorld.offset(oldWorld.nodes[oldIndex].mPrev)
    oldWorld.offset(oldWorld.nodes[oldIndex].mNext)
    oldWorld.offset(oldWorld.nodes[oldIndex].mFirstChild)

  for oldIndex in indexes:
    oldWorld.nodes[oldIndex] = nil
    # oldWorld.offset(oldWorld.nodes[idx].mParent)
    # oldWorld.nodes[oldIndex] = nil

  n.setWorld(w)

proc claimChildren(n: Node) =
  var newWorld = new(World)
  newWorld.isDirty = true
  # n.world.dump(n.name & " pre claimChildren " )
  n.moveToWorld(newWorld)
  # newWorld.dump(n.name & " claimChildren " )

proc removeChild(n: Node, ch: Node) =
  if ch.prev.isNil:
    n.mFirstChild = ch.mNext
    if not ch.next.isNil:
      ch.next.mPrev = InvalidNodeIndex
  else:
    ch.prev.next = ch.next

  ch.parent = nil
  ch.mPrev = InvalidNodeIndex
  ch.mNext = InvalidNodeIndex

  # echo "remove ", ch.name, " from ", n.name
  ch.claimChildren()

proc removeFromParent2*(n: Node) =
  # echo "removeFromParent2 ", n.name
  let parent = n.parent
  if parent.isNil:
    # echo "* removeFromParent2 ", n.name, " parent isNil"
    return
  parent.removeChild(n)

proc addChild2*(n: Node, ch: Node) =
  if not ch.parent.isNil:
    ch.removeFromParent2()
    # ch.mIndex = InvalidNodeIndex

  ch.moveToWorld n.world
  ch.parent = n

  if n.first.isNil:
    n.mFirstChild = ch.mIndex
    ch.mPrev = InvalidNodeIndex
  else:
    n.last.next = ch

proc insertChild2*(n: Node, ch: Node, i: int) =
  if not ch.parent.isNil:
    ch.removeFromParent2()
    # ch.mIndex = InvalidNodeIndex

  ch.moveToWorld n.world
  ch.parent = n

  if i == 0:
    ch.mPrev = InvalidNodeIndex
    if not n.first.isNil:
      ch.next = n.first
    n.mFirstChild = ch.mIndex
    return
  else:
    var idx = 0
    var prev: Node
    for och in n.children:
      if i == idx:
        och.prev.next = ch
        ch.next = och
        return
      prev = och
      inc idx
    if idx == i:
      prev.next = ch
      return
  raise newException(Exception, "Index out of bounds")

proc getRoot(w: World): Node =
  w.nodes[0]

proc reorder*(w: World, indexes: openarray[NodeIndex]) =
  if not w.isDirty or w.nodes.len == 0: return

  template fixUP(v: var NodeIndex) =
    if v != InvalidNodeIndex:
      # echo "fixup ", v
      v = w.nodes[int(v)].mIndex

  var nodes = newSeqOfCap[Node](indexes.len)

  for newIndex, oldIndex in indexes:
    let n = w.nodes[int(oldIndex)]
    n.mIndex = NodeIndex(newIndex)
    nodes.add(n)

  for i, n in nodes:
    n.mIndex = NodeIndex(i)
    n.mParent.fixUP()
    n.mPrev.fixUP()
    n.mNext.fixUP()
    n.mFirstChild.fixUP()

  w.nodes.setLen(0)
  w.nodes = nodes

  w.isDirty = false