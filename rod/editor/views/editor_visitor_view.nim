import nimx / [ view, text_field, button, layout ]

type EditorPropertyVisitorView* = ref object of View
  content*: View
  visitors*: seq[View]
  nameLabel: Label
  onRemoveCb: proc() {.gcsafe.}
  removeButton: Button
  removePlaceholder: View

method init*(v: EditorPropertyVisitorView) =
  procCall v.View.init()
  var dummyContent = new(View)
  dummyContent.makeLayout:
    top == prev.bottom
    leading == super.leading
    trailing == super.trailing
    bottom == super.bottom
    height == 1

  v.removeButton = new(Button)
  v.removeButton.makeLayout:
    frame == super
    width == 20
    title: "X"
    onAction:
      if not v.onRemoveCb.isNil:
        v.onRemoveCb()

  v.makeLayout:
    - Button as btn:
      origin == super
      height == 20
      width == 20
      title: "▼"
      hasBezel: false
      onAction:
        if v.content.superview.isNil:
          btn.title = "▼"
          dummyContent.removeFromSuperview()
          v.addSubview(v.content)
        else:
          btn.title = "▶"
          v.content.removeFromSuperview()
          v.addSubview(dummyContent)

    - Label as name: #dummy
      top == prev
      leading == prev.trailing
      height == prev
      text: "Node"

    - View as removePlaceholder:
      top == prev
      height == prev
      leading == prev.trailing
      trailing == super - 10
      width == 0 @ WEAK

    - View as content:
      top == prev.bottom
      leading == super.leading
      trailing == super.trailing - 10
      bottom == super.bottom
      - View: # dummy for prev in constraints
        top == super
        height == 1
        leading == super.leading
        trailing == super.trailing

  v.content = content
  v.nameLabel = name
  v.removePlaceholder = removePlaceholder

proc addVisitor*(v: EditorPropertyVisitorView, visitor: View) =
  v.content.addSubview(visitor)
  v.visitors.add(visitor)

proc setVisitorName*(v: EditorPropertyVisitorView, name: string) =
  v.nameLabel.text = name

proc onRemove*(v: EditorPropertyVisitorView, cb: proc() {.gcsafe.}) =
  v.onRemoveCb = cb
  v.removePlaceholder.addSubview(v.removeButton)
