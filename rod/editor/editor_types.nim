import ../../ rod / [ rod_types, message_queue ]
import animation / animation_editor_types

const loadingAndSavingAvailable* = not defined(android) and not defined(ios) and
    not defined(emscripten) and not defined(js)

type
  #[
      `editor` - editor state, like changing editing mode
      `composition` - everything related to CompositionDocument like opening, saving etc
      `tree` - Scene Graph realated - add node, remove, reparent
      `node` - Node related, change its properties, add or remove component
      `component` - Component related, change properties of it
      `animation` - Animation related, play, stop
  ]#

  EditorMsgOpCode* {.pure.} = enum
    none
    editor
    composition
    tree
    node
    component

  EditorMessage* = ref object of RootObj
  EditorMessageQueue* = MessageQueue[EditorMessage]

  EditorMode* {.pure.} = enum
    Edit,
    Animation,
    Play

  CompositionDocument* = ref object
    path*: string
    rootNode*: Node
    selectedNode*: Node
    animations*: seq[EditedAnimation]
    currentAnimation*: EditedAnimation