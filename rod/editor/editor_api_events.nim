import ../../ rod / [ message_queue ]
export message_queue

type
  EditorApiEvent* = ref object of RootObj
    kind*: MessageId
  EditorTreeChangedEvent* = ref object of EditorApiEvent
  EditorBaseNodeChangedEvent* = ref object of EditorApiEvent
    path*: seq[int]
  EditorNodeChangedEvent* = ref object of EditorBaseNodeChangedEvent
    property*: string
    value*: string
  EditorNodeRemovedEvent* = ref object of EditorBaseNodeChangedEvent
  EditorNodeAddedEvent* = ref object of EditorBaseNodeChangedEvent
  EditorNodeReparentEvent* = ref object of EditorBaseNodeChangedEvent
    parentPath*: seq[int]
  EditorComponentChangedEvent* = ref object of EditorBaseNodeChangedEvent
    component*: int
    property*: string
    value*: string
