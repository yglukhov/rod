import nimx / [ view, types, layout, text_field, button, formatted_text, segmented_control ]
import tabs / [ editor_tree_view ]
import ../editor_view_types

type LeftPanelView* = ref object of EditorTabPanel
  tree: EditorTreeView

method init*(v: LeftPanelView) =
  procCall v.View.init()

  v.makeLayout:
    backgroundColor: newColor(1.0, 0.8, 0.5, 1.0)
    - SegmentedControl as sc:
      origin == super
      width == super
      height == 20
      segments: @["tree"]
    - EditorTreeView as tree:
      width == super
      top == prev.bottom
      height == super.height - 20

  v.tree = tree

method tabs*(v: LeftPanelView): seq[EditorTabView] =
  result.add(v.tree)