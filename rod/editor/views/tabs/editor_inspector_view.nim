import std/[tables, hashes, sugar]
import nimx / [ view, button, layout, types, text_field, scroll_view, property_visitor, popup_button ]
import nimx/property_editors/[ standard_editors, propedit_registry ]
import ../../../[ node, component, rod_types ]
import ../../../property_editors/standard_editors
import ../../editor_view_types
import ../[editor_visitor_view, editor_add_component_view]
import variant

type EditorInspectorView* = ref object of EditorTabView
  content: View
  currentVisitors: seq[EditorPropertyVisitorView]

method init*(v: EditorInspectorView) =
  procCall v.EditorTabView.init()

  v.makeLayout:
    backgroundColor: whiteColor()
    - ScrollView:
      x == super.x
      y == super.y
      height == super
      width == super
      - View as content:
        width == super

  v.content = content

proc inspectedNodeChanged(v: EditorInspectorView, n: Node) {.gcsafe.}

proc createComponentsView(v: EditorInspectorView, n: Node) {.gcsafe.} =
  var components = new(EditorAddComponentsView)
  components.popupAtPoint(v.convertPointToWindow(v.frame.origin))
  components.onAdd do(component: string):
    echo "adding component ", component
    discard n.addComponent(component)
    v.inspectedNodeChanged(n)

proc inspectedNodeChanged(v: EditorInspectorView, n: Node) {.gcsafe.}=

  proc changeInspectorView() =
    # v.inspectedNodeChanged(n)
    discard

  v.content.removeAllSubviews()
  # proc onChange() =
  #   v.inspectedNodeChanged(n)

  var visitor : PropertyVisitor
  visitor.requireName = true
  visitor.requireSetter = true
  visitor.requireGetter = true
  # if i.editor.mode == emAnimation:
#     visitor.flags = { pfAnimatable }
  # else:
  visitor.flags = { pfEditable }

  var visitorView = new(EditorPropertyVisitorView)
  visitorView.setVisitorName("Node")
  visitorView.makeLayout:
    backgroundColor: newColor(0.123, 0.456, 0.123)
    top == super.top
    leading == super.leading
    trailing == super.trailing

  v.content.addSubview(visitorView)
  v.currentVisitors.add(visitorView)

  var lasPropView: View
  visitor.commit = proc() =
    var propView = propertyEditorForProperty(visitor.name, visitor.setterAndGetter, nil, changeInspectorView)
    propView.makeLayout:
      top == prev.bottom
      leading == super.leading
      trailing == super.trailing
    visitorView.addVisitor(propView)
    lasPropView = propView

  n.visitProperties(visitor)
  if not lasPropView.isNil:
    lasPropView.makeLayout:
      bottom == super.bottom


  var idx = 0

  for com in n.components:
    let componentName = com.className
    visitorView = new(EditorPropertyVisitorView)
    visitorView.setVisitorName(componentName)
    visitorView.makeLayout:
      backgroundColor: uiBlue
      top == prev.bottom
      leading == super.leading
      trailing == super.trailing

    v.content.addSubview(visitorView)
    com.visitProperties(visitor)
    # no properties to visit, so fix layout
    if visitorView.visitors.len == 0:
      visitorView.content.subviews[0].makeLayout:
        bottom == super.bottom
    if not lasPropView.isNil:
      lasPropView.makeLayout:
        bottom == super.bottom

    capture componentName, idx:
      visitorView.onRemove do():
        echo "removing component ", componentName, " at index ", idx
        n.removeComponent(componentName)
        v.inspectedNodeChanged(n)
    inc idx

  var lineView = new(View)
  lineView.makeLayout:
    top == prev.bottom
    leading == super.leading
    trailing == super.trailing
    height == 2
    backgroundColor: blackColor()
  v.content.addSubview(lineView)

  var bottomView = new(View)
  bottomView.makeLayout:
    top == prev.bottom
    bottom == super
    leading == super.leading
    trailing == super.trailing

    - Button as addComponent:
      top == super
      leading == super.leading
      trailing == super.trailing
      height == 16
      height == super
      title: "Add component"
      onAction:
        v.createComponentsView(n)

  v.content.addSubview(bottomView)


method onCompositionChanged*(v: EditorInspectorView, c: CompositionDocument) =
  procCall v.EditorTabView.onCompositionChanged(c)
  # echo "EditorInspectorView onCompositionChanged"

method setInspectedNode*(v: EditorInspectorView, n: Node) =
  # echo "EditorInspectorView selectedNode = ", (if n.isNil: "nil" else: n.name)
  v.inspectedNodeChanged(n)

method onEditorEvent*(v: EditorInspectorView, ev: EditorAPIEvent) =
  if ev.kind == EditorMessageNodeSelectionChanged.toEditorMessageId:
    echo "node selection changed!"
