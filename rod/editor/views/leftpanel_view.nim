import nimx / [ view, types, layout, text_field, button, formatted_text, segmented_control ]
import tabs / [ editor_tab_view, editor_tree_view ]

type LeftPanelView* = ref object of View

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

    # if sc.segments.len == 1:
    #     sc.hidden = true
