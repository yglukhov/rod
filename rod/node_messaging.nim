import rod / [ rod_types, message_queue, node ]

type
  NodeMessage = object
    path: string
    sender: Node
    data: string

  NodeMessageQueue = MessageQueue[NodeMessage]

  MessageSystem* = ref object of BaseSystem
    messageQueue: NodeMessageQueue

proc post*(n: Node, path: string, id: string, data: string = "") =
  if n.sceneView.isNil:
    echo "Node sendMessage \"", id, "\" from node \"", n.name, "\" failed, sceneView is nil!"
    return
  var msg = NodeMessage(path: path, sender: n, data: data)
  n.sceneView.messageQueue.post(id, msg)
