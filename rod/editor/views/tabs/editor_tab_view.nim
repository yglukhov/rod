import nimx / view
import ../../../../rod/[ node ]
import ../../editor_types

type
  EditorTabView* = ref object of View
    composition*: CompositionDocument

method onMessage*(v: EditorTabView, msg: EditorMessage) {.gcsafe, base.} = discard
