import nimx / [ view, layout, animation, button, popup_button, segmented_control, text_field,
  numeric_text_field
]
import ../editor_view_types
import ./editor_animation_types

type
  EditorAnimationToolbar = ref object of View
  EditorAnimationView* = ref object of EditorBaseView

method init*(v: EditorAnimationToolbar) =
  procCall v.View.init()
  let controlSegments = @["","Begin", "Play", "Pause", "Repeat", "End"]
  v.makeLayout:
    - View:
      top == super
      leading == super
      trailing == super
      height == 20
      - Label:
        top == super
        bottom == super
        leading == super
        width == 50
        text:"name:"
      - TextField as name:
        top == super
        bottom == super
        leading == prev.trailing
        width >= 250
        onAction:
          echo "anim name: ", name.text
      - Label:
        top == super
        bottom == super
        leading == prev.trailing
        width == 35
        text:"dur:"
      - NumericTextField as duration:
        top == super
        bottom == super
        leading == prev.trailing
        width == 75
        onAction:
          # echo "anim duraion: ", duration.text
          discard
      - Label:
        top == super
        bottom == super
        leading == prev.trailing
        width == 35
        text:"fps:"
      - NumericTextField as fps:
        top == super
        bottom == super
        leading == prev.trailing
        width == 75
        precision: 0
        onAction:
          # echo "anim duraion: ", fps.text
          discard
      - Button:
        top == super
        bottom == super
        leading == prev.trailing
        width == 50
        title:"Add"
        # font: rodeditIconsFont()
        onAction:
          echo "add animation clicked"
      - Button:
        top == super
        bottom == super
        leading == prev.trailing
        width == 50
        title:"Delete"
        # font: rodeditIconsFont()
        onAction:
          echo "delete animation clicked"
      - Button:
        top == super
        bottom == super
        leading == prev.trailing
        width == 50
        title:"Copy"
        # font: rodeditIconsFont()
        onAction:
          echo "copy animation clicked"
      - PopupButton as selector:
        top == super
        bottom == super
        leading == prev.trailing
        trailing == super
        items: @["one", "two", "tree"]
        onAction:
          echo "animation selected ", selector.selectedItem
    - View:
      top == prev.bottom
      leading == super
      trailing == super
      bottom == super
      - SegmentedControl as control:
        top == super
        bottom == super
        center == super
        width >= 250 @ WEAK
        segments: controlSegments
        onAction:
          echo "control: ", controlSegments[control.selectedSegment]
          control.selectedSegment = 0
method init*(v: EditorAnimationView) =
  procCall v.View.init()

  v.makeLayout:
    backgroundColor: uiBlue
    - EditorAnimationToolbar:
      backgroundColor: uiAccent
      top == super
      leading == super
      trailing == super
      height == 40

method onEditorModeChanged*(v: EditorAnimationView, mode: EditorMode) =
  discard
