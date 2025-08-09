import ./editor_view_types
import nimx / [ types, view, split_view, layout, text_field ]
import views / [ toolbar_view, leftpanel_view, rightpanel_view ]
import ../rod_types

type EditorView* = ref object of EditorBaseView
  toolBar: ToolBarView
  leftPanel: LeftPanelView
  rightPanel: RightPanelView
  centralPart: View
  bottomPart: View
  center: SplitView
  commandsQueue: EditorCommandQueue
  tabs: seq[EditorTabView]
  bb: float

proc setEditorCommandsHandler*(v: EditorView, c: EditorCommandQueue) =
  v.commandsQueue = c
  for tab in v.tabs:
    tab.commandsQueue = c

proc setCurrentComposition*(v: EditorView, c: CompositionDocument) =
  for tab in v.tabs:
    tab.onCompositionChanged(c)

method onEditorEvent*(v: EditorView, ev: EditorAPIEvent) =
  for tab in v.tabs:
    tab.onEditorEvent(ev)

method setInspectedNode*(v: EditorView, n: Node) =
  for tab in v.tabs:
    tab.setInspectedNode(n)

method init*(v: EditorView) =
  procCall v.View.init()

  v.makeLayout:
    backgroundColor: newColor(0.0, 0.0, 0.0, 1.0)
    - ToolBarView as toolbar:
      origin == super
      width == super
      height == 30.0

    - SplitView:
      y == 30.0
      height == super - 30.0
      width == super
      vertical: false
      resizable: true

      - LeftPanelView as leftPanel:
        x == 0
        width == 250 @ WEAK
        350 >= self.width
        self.width >= 150
        height == super

      - View:
        leading == prev.trailing
        y == super
        height == super
        width >= 150
        backgroundColor: newColor(1.4, 0.8, 0.3, 1.0)

        - SplitView as center:
          x == super
          y == super
          width == super
          height == super
          vertical: true
          resizable: true

          - View as centralPart:
            y == super
            width == super
            backgroundColor: newColor(0.133, 0.545, 0.133, 1.0)
            - Label:
              text: "Middle up"
              origin == super + 15

          - View as bottomPart:
            width == super
            height == 150 @ WEAK
            backgroundColor: newColor(0.0, 0.749, 1.0, 1.0)
            - Label:
              text: "Middle bottom"
              origin == super + 15

      - RightPanelView as rightPanel:
        leading == prev.trailing
        width == 250 @ WEAK
        450 >= self.width
        self.width >= 200
        height == super

  v.toolBar = toolbar
  v.leftPanel = leftPanel
  v.centralPart = centralPart
  v.bottomPart = bottomPart
  v.rightPanel = rightPanel

  v.tabs.add(v.leftPanel.tabs)
  v.tabs.add(v.rightPanel.tabs)

  v.toolBar.onViewClicked = proc() =
    # v.bottomPart.hidden = not v.bottomPart.hidden
    if v.bottomPart.superview.isNil:
      center.addSubview(v.bottomPart)
      center.setDividerPosition(v.bb, 0)
    else:
      v.bb = center.dividerPosition(0)
      v.bottomPart.removeFromSuperview()

  echo "EditorView ini: ", v.leftPanel != nil