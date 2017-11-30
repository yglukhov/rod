import nimx / [ panel_view, text_field, button, view,
    types, matrixes, formatted_text, layout]

type
    EditorDialog* = ref object of PanelView
        titleLabel: TextField
        closeButton: Button
        content*: View
        lockInput*: bool

proc `title=`*(ed: EditorDialog, t: string)=
    ed.titleLabel.text = t

proc title*(ed: EditorDialog): string=
    ed.titleLabel.text

method close*(ed: EditorDialog) {.base.} =
    ed.removeFromSuperview()

method init*(ed: EditorDialog, r: Rect)=
    procCall ed.PanelView.init(r)

    ed.makeLayout:
        - TextField as titleLabel:
            top == 20
            leading == super
            width == super - 20
            height == 20
            text: "EditorDialog title"
            textColor: whiteColor()

        - Button as closeButton:
            title: "x"
            top == prev
            leading == prev.width
            width == 20
            height == 20
            onAction:
                ed.close()

        - View as content:
            leading == 10
            top == prev.bottom
            width == super - 10
            bottom == super - 10
            backgroundColor: newColor(1.0, 1.0, 1.0, 0.7)

    ed.titleLabel = titleLabel
    ed.closeButton = closeButton
    ed.content = content

    ed.titleLabel.formattedText.boundingSize = newSize(ed.titleLabel.bounds.width, 20.0)
    ed.titleLabel.formattedText.verticalAlignment = vaCenter
    ed.titleLabel.formattedText.horizontalAlignment = haCenter
