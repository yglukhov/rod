import std/[tables, algorithm, sugar]
import nimx / [app, types, view, button, layout, scroll_view, text_field]
import ../../[component]
import ../[editor_view_types]

type EditorAddComponentsView* = ref object of View
  addCallback: proc(c: string) {.gcsafe.}

method init*(v: EditorAddComponentsView) =
  procCall v.View.init()
  v.makeLayout:
    backgroundColor: uiYellow
    width == 400
    height == super
    - Label as filter:
      origin == super
      width == super - 20
      height == 20
      text: "Components:"
    - Button:
      leading == prev.trailing
      trailing == super.trailing
      height == 20
      top == prev
      title:"X"
      onAction:
        v.removeFromSuperview()
    - ScrollView:
      top == prev.bottom
      leading == super.leading
      trailing == super.trailing
      bottom == super
      - View as content:
        backgroundColor: uiLavender
        width == super
        - View:
          top == super
          height == 1
          leading == super
          trailing == super

  var lastGroup: View
  for groupName, componentsInGroup in componentGroupsTable:
    var group = new(View)
    lastGroup = group
    group.makeLayout:
      backgroundColor: uiGray
      top == prev.bottom
      leading == super
      trailing == super
      - Label:
        top == super
        height == 20
        leading == super
        trailing == super
        text: groupName
      - View:
        top == prev.bottom
        height == 1
        leading == super
        trailing == super

    var componentsList = componentsInGroup
    sort(componentsList, system.cmp)
    var lastView: View
    for component in componentsList:
      var view = new(View)
      lastView = view
      capture component:
        view.makeLayout:
          backgroundColor: uiPeach
          top == prev.bottom
          leading == super
          trailing == super
          - Button:
            backgroundColor: uiBlue
            title: component
            top == super
            height == 20
            leading == super
            trailing == super
            bottom == super
            hasBezel: false
            onAction:
              if not v.addCallback.isNil:
                v.addCallback(component)
                v.removeFromSuperview()
      group.addSubview(view)
    content.addSubview(group)

    lastView.makeLayout:
      bottom == super.bottom

  lastGroup.makeLayout:
    bottom == super.bottom


proc onAdd*(v: EditorAddComponentsView, cb: proc(c: string) {.gcsafe.}) =
  v.addCallback = cb
