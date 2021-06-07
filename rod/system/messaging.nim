import rod / [ rod_types, message_queue, node, systems, viewport, component ]
import strutils, typetraits, logging

export message_queue, systems

type
  NodeMessage = object
    path: string
    sender: Node
    data: string

  NodeMessageQueue = MessageQueue[NodeMessage]

  MessageSystem* = ref object of System
    messageQueue: NodeMessageQueue

method onMessage*(c: ScriptComponent, id: MessageId, data: string, sender: Node) {.base.} = discard

method init*(s: MessageSystem) =
  s.messageQueue = createMessageQueue[NodeMessage]()

proc proceedMessage(s: MessageSystem, id: MessageId, msg: NodeMessage) =
  var sp = msg.path.split("/")
  var targetComponent = ""
  let lsp = sp[^1].split("#")
  if lsp.len > 1:
    sp[^1] = lsp[0]
    targetComponent = lsp[1]

  var receiver: Node
  try:
    receiver = msg.sender.findNode(sp)
  except Exception as e:
    warm "receiver not found ", sp, " ", e.msg

  if receiver.isNil:
    warn "receiver not found ", sp
    return

  if targetComponent.len == 0:
    warn "to target component"
    return

  let comp = receiver.componentIfAvailable(targetComponent)
  if comp.isNil or comp.isRenderComponent: return
  comp.ScriptComponent.onMessage(id, msg.data, msg.sender)

method update*(s: MessageSystem, dt: float) =
  for id, msg in s.messageQueue.popChunk(chunk = 50):
    s.proceedMessage(id, msg)

proc post(s: MessageSystem, id: string, msg: NodeMessage) =
  s.messageQueue.post(id, msg)

proc post*(n: Node, path: string, id: string, data: string = "") =
  if n.sceneView.isNil:
    warn "Node sendMessage \"", id, "\" from node \"", n.name, "\" failed, sceneView is nil!"
    return
  var msg = NodeMessage(path: path, sender: n, data: data)
  n.sceneView.system(MessageSystem).post(id, msg)

registerSystem(MessageSystem)
