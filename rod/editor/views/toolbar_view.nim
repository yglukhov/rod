import nimx / [ view, types, layout, text_field, button, formatted_text ]

type
  # ToolButtonKind* {.pure.} = enum
  #   file, edit,
  # ToolBarButton* = ref object of Button

  ToolBarView* = ref object of View
    onViewClicked*: proc() {.gcsafe.}
    onAnimationClicked*: proc() {.gcsafe.}

method init*(v: ToolBarView) =
  procCall v.View.init()

  v.makeLayout:
    backgroundColor: newColor(1.0, 1.0, 0.7, 1.0)
    - Button as file:
      width >= 100
      y == super
      height == super
      x == super
      title: "File"
      onAction:
        echo "File Clicked"

    - Button:
      width >= 100
      y == prev.y
      height == super
      x == prev.trailing
      title: "View"
      onAction:
        if not v.onViewClicked.isNil:
          v.onViewClicked()

    - Button:
      width >= 100
      y == prev.y
      height == super
      x == prev.trailing
      title: "Animation"
      onAction:
        if not v.onAnimationClicked.isNil:
          v.onAnimationClicked()

    - Label:
      y == super
      height == super
      # 250 >= self.width
      text: "version: 135"
      width >= 150
      trailing == super.width
      backgroundColor: newColor(0.8, 1.0, 0.66, 1.0)
      horizontalAlignment: haCenter
      # origin == super + 15
