type
  EditorMessage* = ref object of RootObj

  EditorMessageAddNode* = ref object of EditorMessage
    parentPath*: seq[int]
    nodeName*: string

  EditoMessageRemoveNode* = ref object of EditorMessage
    path*: seq[int]

  EditorMessageReparentNode* = ref object of EditorMessage
    fromPath*: seq[int]
    toPath*: seq[int]

  EditorMessageNodeSelectionChanged* = ref object of EditorMessage
    path*: seq[int]