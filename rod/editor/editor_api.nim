import ../../ rod / [ rod_types, message_queue ]
import ./editor_composition
export message_queue

type
  #[
      `editor` - editor state, like changing editing mode
      `composition` - everything related to CompositionDocument like opening, saving etc
      `tree` - Scene Graph realated - add node, remove, reparent
      `node` - Node related, change its properties, add or remove component
      `component` - Component related, change properties of it
      `animation` - Animation related, play, stop, pause
  ]#

  EditorCommand* {.pure.} = enum
    none = "invalid".toMessageId
    tree = "tree".toMessageId
    node = "node".toMessageId
    component = "component".toMessageId
    animation = "animation".toMessageId

  EditorMessage* = ref object of RootObj
  EditorMessageQueue* = MessageQueue[EditorMessage]

  EditorMessageAddNode* = ref object of EditorMessage
    parentPath*: seq[int]
    nodeName*: string

  EditoMessageRemoveNode* = ref object of EditorMessage
    path*: seq[int]

  EditorMessageReparentNode* = ref object of EditorMessage
    fromPath*: seq[int]
    toPath*: seq[int]

type
  EditorAPI* = ref object of RootObj
  EditorCommandQueue* = ref object of RootObj

method move*(api: EditorAPI, queue: EditorMessageQueue) {.base, gcsafe.} = discard

method post*(e: EditorCommandQueue, cmd: EditorCommand, msg: EditorMessage) {.base, gcsafe.} = discard
