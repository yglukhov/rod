import ./editor_view_types
import nimx / [ types, view, split_view, layout, text_field, clip_view ]
import views / [ toolbar_view, leftpanel_view, rightpanel_view ]
import ../rod_types
import ./views/tabs/[ editor_scene_view]
import ./assets/editor_assets_view
import ./animation/editor_animation_view

type EditorView* = ref object of EditorBaseView
  toolBar: ToolBarView
  leftPanel: LeftPanelView
  rightPanel: RightPanelView
  sceneView: EditorSceneView
  bottomPart: EditorAssetsView
  center: SplitView
  commandsQueue: EditorCommandQueue
  tabs: seq[EditorTabView]
  bb: float

proc setEditorCommandsHandler*(v: EditorView, c: EditorCommandQueue) =
  v.commandsQueue = c
  for tab in v.tabs:
    tab.setApi(c)

proc setCurrentComposition*(v: EditorView, c: CompositionDocument) =
  for tab in v.tabs:
    tab.onCompositionChanged(c)

proc setEditorMode*(v: EditorView, mode: EditorMode) =
  for tab in v.tabs:
    tab.onEditorModeChanged(mode)

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

          - ClipView:
            y == super
            width == super
            - EditorSceneView as sceneView:
              frame == super

          - View as bottomPlac:
            width == super
            height == 150 @ WEAK
            - EditorAssetsView as bottomPart:
              frame == super

      - RightPanelView as rightPanel:
        leading == prev.trailing
        width == 250 @ WEAK
        450 >= self.width
        self.width >= 200
        height == super

  var animationEditor = new(EditorAnimationView)
  animationEditor.makeLayout:
    frame == super

  v.toolBar = toolbar
  v.leftPanel = leftPanel
  v.sceneView = sceneView
  v.bottomPart = bottomPart
  v.rightPanel = rightPanel

  v.tabs.add(v.sceneView)
  v.tabs.add(v.leftPanel.tabs)
  v.tabs.add(v.rightPanel.tabs)

  v.toolBar.onViewClicked = proc() =
    if bottomPlac.superView.isNil:
      center.addSubview(bottomPlac)
      center.setDividerPosition(v.bb, 0)
    else:
      v.bb = center.dividerPosition(0)
      bottomPlac.removeFromSuperview()

  v.toolBar.onAnimationClicked = proc() =
    if v.bottomPart.superview.isNil:
      bottomPlac.addSubview(v.bottomPart)
      animationEditor.removeFromSuperview()
      v.setEditorMode(EditorMode.edit)
    else:
      v.bottomPart.removeFromSuperview()
      bottomPlac.addSubview(animationEditor)
      v.setEditorMode(EditorMode.animation)
