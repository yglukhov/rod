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
    - Label as name: #dummy
      origin == super
      height == 20
      width == super.width - 100
      text: "Node"

    - Button as btn:
      top == prev.top
      height == prev.height
      x == prev.trailing
      # width >= 80
      trailing == next.leading
      title: "Hide"
      onAction:
        if v.content.superview.isNil:
          btn.title = "Hide"
          dummyContent.removeFromSuperview()
          v.addSubview(v.content)
        else:
          btn.title = "Show"
          v.content.removeFromSuperview()
          v.addSubview(dummyContent)

    - View as removePlaceholder:
      top == prev
      trailing == super
      height == prev
      width == 0 @ WEAK

    - View as content:
      top == prev.bottom
      leading == super.leading
      trailing == super.trailing
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
