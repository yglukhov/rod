import system
import ../[ rod_types, node, message_queue ]
import ./[editor_api, editor_composition]

type
  EditorServer* = ref object of EditorAPI
    rootNode*: Node
    listner: EditorApiListner

proc notify[T: EditorApiEvent](e: EditorServer, msg: T) =
  msg.kind = T.toEditorMessageId
  if not e.listner.isNil:
    e.listner(msg)

proc node(e: EditorServer, path: seq[int]): Node =
  result = e.rootNode.nodeAtPath(path)

proc treeAddNode(e: EditorServer, msg: EditorMessageAddNode) =
  sandbox:
    echo "add node at ", msg.parentPath
    e.node(msg.parentPath).addChild(newNode(msg.nodeName))
    e.notify(EditorTreeChangedEvent())

proc treeRemoveNode(e: EditorServer, msg: EditoMessageRemoveNode) =
  sandbox:
    echo "remove node at ", msg.path
    var node = e.node(msg.path)
    if node != e.rootNode:
      node.removeFromParent()
      e.notify(EditorTreeChangedEvent())

proc treeReparentNode(e: EditorServer, msg: EditorMessageReparentNode) =
  sandbox:
    echo "reparent node from", msg.fromPath, " to ", msg.toPath
    let fromNode = e.node(msg.fromPath)
    var tos = msg.toPath
    tos.setLen(tos.len - 1)
    let toNode = e.node(tos)
    let toIndex = msg.toPath[^1]
    if fromNode.parent == toNode:
      let cIndex = toNode.children.find(fromNode)
      if toIndex < cIndex:
        toNode.children.delete(cIndex)
        toNode.children.insert(fromNode, toIndex)
      elif toIndex > cIndex:
        toNode.children.delete(cIndex)
        toNode.children.insert(fromNode, toIndex - 1)
    else:
      fromNode.removeFromParent()
      toNode.insertChild(fromNode, toIndex)

    e.notify(EditorTreeChangedEvent())

method setRootNodeLocally*(e: EditorServer, node: Node) =
  e.rootNode = node

method setEventListner*(e: EditorServer, listner: proc(event: EditorApiEvent) {.gcsafe.}) =
  e.listner = listner

method consumeLocally*(e: EditorServer, cmd: MessageId, msg: EditorMessage) =
  #TODO: add msgs to undo queue?
  case cmd
  of EditorMessageAddNode.toEditorMessageId:
    e.treeAddNode(cast[EditorMessageAddNode](msg))
  of EditoMessageRemoveNode.toEditorMessageId:
    e.treeRemoveNode(cast[EditoMessageRemoveNode](msg))
  of EditorMessageReparentNode.toEditorMessageId:
    e.treeReparentNode(cast[EditorMessageReparentNode](msg))
  else:
    echo "unknown command ", cmd
