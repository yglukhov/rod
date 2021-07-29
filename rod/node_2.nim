import rod / [ rod_types, node_flags ]
import sequtils

# type
#   World = ref object
#     nodes: seq[Node]
#     isDirty: bool

#   NodeIndex = uint16

#   Node = ref object of RootObj
#     name: string
#     isDirty: bool
#     mIndex: NodeIndex
#     mParent: NodeIndex
#     mNext: NodeIndex
#     mPrev: NodeIndex
#     mFirstChild: NodeIndex
#     mWorld: World


# const InvalidIndex = high(NodeIndex)

# proc newNode(name: string): Node

proc setDirty*(n: Node)

const InvalidNodeIndex* = high(NodeIndex)

proc addNode(w: World, n: Node): NodeIndex =
  result = w.nodes.len.NodeIndex
  w.nodes.add(n)
  w.isDirty = true

proc getNode(w: World, i: NodeIndex): Node =
  if i < w.nodes.len.NodeIndex:
    return w.nodes[i]

proc reorder*(w: World)

proc dump(w: World, prefix: string = "") =
  for n in w.nodes:
    echo prefix, n.mIndex, " : ", n.name, " [par ", n.mParent, ", fst ", n.mFirstChild, ", prv ", n.mPrev, ", nxt ", n.mNext, "]"

proc parent*(n: Node): Node

proc moveToWorld(n: Node, w: World)

proc world(n: Node): World =
  if not n.mWorld.isNil:
    return n.mWorld
  n.mWorld = new(World)
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
    echo n.name, " parent= nil"
    n.mParent = InvalidNodeIndex
  else:
    echo n.name, " parent= ", p.name, " index ", p.mIndex
    n.mParent = p.mIndex
  n.setDirty()

proc last*(n: Node): Node =
  result = n.first
  if result.isNil: return
  while not result.next.isNil:
    result = result.next

iterator children*(n: Node): Node =
  var el = n.first
  var iters = 0
  while not el.isNil:
    yield el
    el = el.next
    if iters > n.world.nodes.len:
      raise newException(Exception, "looped ")
    inc iters

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

proc printWorld(w: World) =
  echo "\nWORLD "
  for node in w.nodes:
    echo node.mIndex, " : ", node.name


proc setDirty*(n: Node) =
  if not n.isDirty:
    n.isDirty = true
    for c in n.children:
      c.setDirty()

proc offsetIndexes(n: Node, off: int, fromIndex: NodeIndex = InvalidNodeIndex) =
  template offset(field: var NodeIndex) =
    if field != InvalidNodeIndex:
      field = NodeIndex(int(field) + off)

  # echo "  * offsetIndexes ", n.name, " off ", off, " fromIndex ", fromIndex
  offset(n.mIndex)
  offset(n.mNext)
  offset(n.mFirstChild)

  if not n.prev.isNil:
    n.prev.mNext = n.mIndex
  elif not n.parent.isNil:
    n.parent.mFirstChild = n.mIndex

  if fromIndex == InvalidNodeIndex or n.mParent > fromIndex:
    offset(n.mParent)

  if fromIndex == InvalidNodeIndex or n.mPrev > fromIndex:
    offset(n.mPrev)

proc getOrder(node: Node, order: var seq[NodeIndex]) =
  order.add(node.mIndex)
  # echo "getOrder ", node.name
  for ch in node.children:
    getOrder(ch, order)

proc moveTo(w1, w2: World, indexes: seq[NodeIndex]) =
  var nodes: seq[Node]
  for i in indexes:
    nodes.add(w1.nodes[int(i)])

proc setWorld(n: Node, w: World) =
  n.mWorld = w
  for ch in n.children:
    ch.setWorld(w)

proc moveToWorld(n: Node, w: World) =
  echo "moveToWorld ", n.name, " world ", w.nodes.len
  if n.mWorld.isNil:
    n.mWorld = w
    n.mIndex = w.addNode(n)
    n.setWorld(w)
    w.isDirty = true
    w.reorder()
    return
  if n.mWorld == w:
    w.isDirty = true
    w.reorder()
    return

  let oldWorld = n.mWorld
  oldWorld.dump("ss ")

  var indexes: seq[NodeIndex]
  # indexes.add(n.mIndex)
  # oldWorld.dump("old0 ")
  getOrder(n, indexes)
  # oldWorld.moveTo(w, indexes)

  oldWorld.reorder()
  w.reorder()

  # echo "moveToWorld2 ", indexes
  for idx in indexes:
    let node = oldWorld.nodes[idx]
    let newIndex = w.addNode(node)
    # echo "  offsetIndexe2 ", int(newIndex) - int(idx)
    node.offsetIndexes(int(newIndex) - int(idx))
  n.setWorld(w)

  for i in indexes[^1].int + 1 ..< oldWorld.nodes.len:
    # echo "offset ", oldWorld.nodes[i].name, " from ", indexes[0]
    oldWorld.nodes[i].offsetIndexes(-indexes.len, indexes[0])
  oldWorld.nodes.delete(first = indexes[0].int, last = indexes[^1].int)

  oldWorld.isDirty = true
  oldWorld.reorder()

  w.isDirty = true
  w.reorder()
  # echo "  moved"

proc claimChildren(n: Node) =
  var newWorld = new(World)
  newWorld.isDirty = true
  let oldW = n.world
  # n.world.dump("z ")
  n.moveToWorld(newWorld)
  # n.world.reorder()
  # n.world.reorder()
  # n.world.dump("x ")
  # oldW.dump("z2 ")

proc removeChild(n: Node, child: Node) =
  var prev: Node
  for ch in n.children:
    if ch == child:
      ch.parent = nil
      if prev.isNil:
        n.mFirstChild = ch.mNext
      else:
        prev.next = ch.next
      ch.mNext = InvalidNodeIndex
      ch.mPrev = InvalidNodeIndex
      echo "remove ", ch.name, " from ", n.name
      ch.claimChildren()
      break
    prev = ch

proc removeFromParent2*(n: Node) =
  let parent = n.parent
  if parent.isNil:
    echo "removeFromParent2 ", n.name, " parent isNil"
    return
  parent.removeChild(n)

proc addChild2*(n: Node, ch: Node) =
  echo "\nadd ", ch.name, " to ", n.name
  if ch.mIndex != InvalidNodeIndex:
    ch.removeFromParent2()

  # n.world.reorder()
  ch.moveToWorld n.world
  # ch.mIndex = n.world.addNode(ch)
  ch.parent = n

  if n.first.isNil:
    n.mFirstChild = ch.mIndex
    ch.mPrev = InvalidNodeIndex
  else:
    n.last.next = ch
  # n.printTree()
  # n.world.printWorld()

proc insertChild2*(n: Node, ch: Node, i: int) =
  if ch.mIndex != InvalidNodeIndex:
    ch.removeFromParent2()

  # ch.mIndex = n.world.addNode(ch)
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

proc swapNodes(w: World, targetIndex, oldIndex: NodeIndex) =
  let node = w.nodes[oldIndex]
  let node2 = w.nodes[targetIndex]
  let parent = node.parent
  let parent2 = node2.parent
  let first = parent.first
  let first2 = parent2.first

  for ch in node.children:
    ch.mParent = targetIndex
  for ch in node2.children:
    ch.mParent = oldIndex

  if first == node:
    parent.mFirstChild = targetIndex
  if first2 == node2:
    parent2.mFirstChild = oldIndex
  node.mIndex = targetIndex
  node2.mIndex = oldIndex

  let prev = node.prev
  let prev2 = node2.prev
  let next = node.next
  let next2 = node2.next
  if not prev.isNil:
    prev.mNext = targetIndex
  if not prev2.isNil:
    prev2.mNext = oldIndex
  if not next.isNil:
    next.mPrev = targetIndex
  if not next2.isNil:
    next2.mPrev = oldIndex
  swap(w.nodes[oldIndex], w.nodes[targetIndex])

proc getRoot(w: World): Node =
  w.nodes[0]

proc reorder*(w: World) =
  if not w.isDirty or w.nodes.len == 0: return

  # w.dump("Before ")
  var swaps: seq[NodeIndex]
  getOrder(w.getRoot(), swaps)

  var index = 0
  while index < swaps.len:
    var swap = swaps[index]
    if index.NodeIndex == swap:
      inc index
      continue
    w.swapNodes(index.NodeIndex, swap)
    for i in 0 ..< swaps.len:
      if i <= index:
        swaps[i] = InvalidNodeIndex
      if swaps[i] == index.NodeIndex:
        swaps[i] = swap
        break
    # w.getRoot().printTree()
    inc index


  w.isDirty = false

  # w.dump("After ")
  # w.getRoot().printTree()

# proc newNode(name: string): Node =
#   result = new(Node)
#   result.name = name
#   result.mParent = InvalidIndex
#   result.mIndex = InvalidIndex
#   result.mNext = InvalidIndex
#   result.mPrev = InvalidIndex
#   result.mFirstChild = InvalidIndex

# proc newChild(n: Node, name: string): Node =
#   result = newNode(name)
#   n.addChild2(result)
#   echo name, " parent valid ", not result.parent.isnil, " parent index ", result.mParent
#   echo ""

# var root = newNode("root")

# var scene = root.newChild("Scene")
# var gui = root.newChild("GUI")

# var topPanel = gui.newChild("top")
# var bottom = gui.newChild("bottom")

# var game1 = scene.newChild("game1")
# var game2 = scene.newChild("game2")

# var debug = root.newChild("Debug")
# var d1 = debug.newChild("deg")

# template test(name: string, body: untyped) =
#   echo "\n"
#   echo name
#   body
#   echo "tree:"
#   root.printTree()
#   echo "world"
#   root.world.dump()

# test "dump all":
#   # root.world.dump()
#   discard

# test "gui remove from root":
#   gui.removeFromParent2()

# test "add gui to debug":
#   debug.addChild2(gui)

# test "add debug to game1":
#   game1.addChild2(debug)

# test "insert debug to root":
#   root.insertChild2(debug, 1)

# test "return gui to root":
#   root.insertChild2(gui, 1)

# test "reorder":
#   root.world.dump()
#   root.world.reorder()
#   root.world.dump()
#   root.printTree()
