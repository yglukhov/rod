import nimx / [ view, button, layout, types, text_field, scroll_view ]
import ../../../../rod/[ node ]
import ../../editor_types

type EditorInspectorView* = ref object of EditorTabView

method init*(v: EditorInspectorView) =
  procCall v.EditorTabView.init()

  v.makeLayout:
    backgroundColor: whiteColor()
    - Label:
      origin == super
      width == super - 20
      height == 20
      text: "Auto update:"

    - Checkbox as autoUpdate:
      x == prev.x + prev.width
      y == prev.y
      height == 20
      width == 20
      onAction:
        echo "checked ", autoUpdate.boolValue

    - ScrollView:
      x == super.x
      y == 20
      height == super - 20
      width == super


method onCompositionChanged*(v: EditorInspectorView, c: CompositionDocument) =
  procCall v.EditorTabView.onCompositionChanged(c)
  echo "EditorInspectorView onCompositionChanged"
