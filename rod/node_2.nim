import rod / [ rod_types, node_flags ]

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

proc removeNode(w: World, i: NodeIndex) =
  if i < w.nodes.len.NodeIndex:
    # we will remove this nodes in reorder
    w.nodes.del(i)
    w.isDirty = true
    ## todo: handle id changing

proc dump(w: World) =
  for n in w.nodes:
    echo n.mIndex, " : ", n.name

proc parent*(n: Node): Node

proc moveToWorld(n: Node, w: World)

proc world(n: Node): World =
  var scene = n.mSceneView
  if not scene.isNil:
    return scene.world
  if not n.mWorld.isNil:
    return n.mWorld
  n.mWorld = new(World)
  result = n.mWorld

proc first*(n: Node): Node =
  if n.world.isnil: return
  return n.world.getNode(n.mFirstChild)

proc next(n: Node): Node =
  if n.world.isnil: return
  return n.world.getNode(n.mNext)

proc `next=`(n: Node, nn: Node) =
  if nn.isNil:
    n.mNext = InvalidNodeIndex
    return
  n.mNext = nn.mIndex
  nn.mPrev = n.mIndex

proc prev(n: Node): Node =
  if n.world.isnil: return
  return n.world.getNode(n.mPrev)

proc parent*(n: Node): Node =
  if n.world.isnil: return
  return n.world.getNode(n.mParent)

proc `parent=`*(n: Node, p: Node) =
  if p.isNil:
    n.mParent = InvalidNodeIndex
  else:
    n.mParent = p.mIndex
  n.setDirty()

proc last*(n: Node): Node =
  result = n.first
  if result.isNil: return
  while not result.next.isNil:
    result = result.next

iterator children*(n: Node): Node =
  var el = n.first
  while not el.isNil:
    yield el
    el = el.next

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

proc claimChildren(n: Node) =
  var newWorld = new(World)
  newWorld.nodes.add(n)
  for ch in n.children:
    discard newWorld.addNode(ch)
  for node in newWorld.nodes:
    n.world.removeNode(node.mIndex)
  #reorder old world
  n.world.reorder()
  # set new world
  n.mWorld = newWorld

proc removeChild(n: Node, child: Node) =
  var prev: Node
  for ch in n.children:
    if ch == child:
      ch.parent = nil
      if prev.isNil:
        n.mFirstChild = ch.mNext
      else:
        prev.mNext = ch.mNext
      ch.mNext = InvalidNodeIndex
      echo "remove ", ch.name, " from ", n.name
      ch.claimChildren()
      break
    prev = ch

proc removeFromParent2*(n: Node) =
  let parent = n.parent
  if parent.isNil: #root node
    return
  parent.removeChild(n)

proc addChild2*(n: Node, ch: Node) =
  echo " add ", ch.name, " to ", n.name
  n.world.isDirty = true
  if ch.mIndex != InvalidNodeIndex:
    ch.removeFromParent2()
    ch.mIndex = InvalidNodeIndex

  ch.mIndex = n.world.addNode(ch)
  ch.moveToWorld n.world
  ch.parent = n

  if n.first.isNil:
    n.mFirstChild = ch.mIndex
    ch.mPrev = InvalidNodeIndex
  else:
    n.last.next = ch
  # n.printTree()
  n.world.printWorld()

proc insertChild2*(n: Node, ch: Node, i: int) =
  n.world.isDirty = true
  if ch.mIndex != InvalidNodeIndex:
    ch.removeFromParent2()
    ch.mIndex = InvalidNodeIndex

  ch.mIndex = n.world.addNode(ch)
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

#[
  mIndex*: NodeIndex
  mParent*: NodeIndex
  mNext*: NodeIndex
  mPrev*: NodeIndex
  mFirstChild*: NodeIndex
]#

proc offsetIndexes(n: Node, offset: int) =
  n.mIndex = NodeIndex(int(n.mIndex) + offset)
  n.mParent = NodeIndex(int(n.mParent) + offset)
  n.mNext = NodeIndex(int(n.mNext) + offset)
  n.mPrev = NodeIndex(int(n.mPrev) + offset)
  n.mFirstChild = NodeIndex(int(n.mFirstChild) + offset)

proc moveToWorld(n: Node, w: World) =
  if n.mWorld.isNil:
    n.mWorld = w
    return
  for node in n.mWorld.nodes:
    let oldIndex = node.mIndex
    let newIndex = w.addNode(node)
    echo "offsetIndexes ", int(newIndex) - int(oldIndex)
    node.offsetIndexes(int(newIndex) - int(oldIndex))
  n.mWorld = w

# proc moveToWorld(n: Node, w: World) =
#   let startIndex = w.nodes.len
#   var oldIndexes: seq[NodeIndex]

#   for n in n.world:
#     oldIndexes.add(n.mIndex)
#     n.offsetIndexes(startIndex)
#   for i in oldIndexes:
#     w.add(n.world[i])
#     n.world[i] = nil #todo: think about it...
#   n.wolrd.isDirty = true
#   w.isDirty = true

# proc removeFromWorld(n: Node) =
#   let oldWorld = n.world
#   let offset = n.mIndex
#   n.world = new(World)

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

proc getOrder(w: World, node: Node, order: var seq[NodeIndex]) =
  for ch in node.children:
    order.add(ch.mIndex)
    w.getOrder(ch, order)

proc getRoot(w: World): Node =
  w.nodes[0]

proc reorder*(w: World) =
  if not w.isDirty: return

  echo "Before"
  w.printWorld()
  w.getRoot().printTree()
  var swaps: seq[NodeIndex]
  swaps.add(0.NodeIndex)
  w.getOrder(w.getRoot(), swaps)

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
    w.getRoot().printTree()
    inc index

  w.isDirty = false

  echo "After"
  w.printWorld()
  w.getRoot().printTree()
