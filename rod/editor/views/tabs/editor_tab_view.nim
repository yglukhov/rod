import nimx / view
import ../../editor_types

type EditorTabView* = ref object of View
    composition*: CompositionDocument