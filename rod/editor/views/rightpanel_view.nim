import nimx / [ view, types, layout, text_field, button, formatted_text, segmented_control ]
import tabs / [ editor_tab_view, editor_inspector_view ]

type RightPanelView* = ref object of View

method init*(v: RightPanelView) =
  procCall v.View.init()

  v.makeLayout:
    - SegmentedControl as sc:
      origin == super
      width == super
      height == 20
      segments: @["inspector"]

    - EditorInspectorView as tree:
      x == super.x
      y == super.y + 20
      width == super
      top == prev.bottom
      height == super.height - 20
