import nimx / [ view, types, layout, text_field, button, formatted_text, segmented_control ]
import tabs / [  editor_inspector_view ]
import ../editor_view_types

type RightPanelView* = ref object of EditorTabPanel
  inspector*: EditorInspectorView

method init*(v: RightPanelView) =
  procCall v.View.init()

  v.makeLayout:
    - SegmentedControl as sc:
      origin == super
      width == super
      height == 20
      segments: @["inspector"]

    - EditorInspectorView as inspector:
      x == super.x
      y == super.y + 20
      width == super
      top == prev.bottom
      height == super.height - 20

  v.inspector = inspector

method tabs*(v: RightPanelView): seq[EditorTabView] =
  result.add(v.inspector)
