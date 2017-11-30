
import nimx / [ view, button, text_field, formatted_text, window ]

import editor_dialog
export editor_dialog

type EditorConfirmDialog* = ref object of EditorDialog
    questionField: TextField
    acceptButton: Button
    cancelButton: Button

proc `question=`*(ed: EditorConfirmDialog, q: string)=
    ed.questionField.text = q

import nimx.layout

method init*(ed: EditorConfirmDialog, r: Rect)=
    procCall ed.EditorDialog.init(r)

    ed.content.makeLayout:
        origin == super
        size == super

        - TextField as questionField:
            leading == super + 5
            top == super + 5
            trailing == super - 5

        - Button as acceptButton:
            top == prev.bottom + 10
            width == 45
            trailing == super.centerX - 5
            bottom == super - 5
            title: "Yes"

        - Button as cancelButton:
            top == prev
            size == prev
            leading == super.centerX + 5
            title: "No"

    ed.questionField = questionField
    ed.acceptButton = acceptButton
    ed.cancelButton = cancelButton

    let cr = ed.content.bounds
    # ed.questionField = newLabel(newRect(5.0, 5.0, cr.width - 10.0, cr.height - 30.0))
    ed.questionField.formattedText.boundingSize= newSize(cr.width - 10.0, cr.height - 30.0)
    ed.questionField.formattedText.horizontalAlignment = haCenter
    ed.questionField.formattedText.verticalAlignment = vaCenter
    # ed.content.addSubview(ed.questionField)

    # ed.acceptButton = newButton(newRect(cr.width * 0.5 - 45.0, cr.height - 30.0, 40.0, 20.0))
    # ed.acceptButton.title = "YES"
    # ed.content.addSubview(ed.acceptButton)

    # ed.cancelButton = newButton(newRect(cr.width * 0.5 + 45.0, cr.height - 30.0, 40.0, 20.0))
    # ed.cancelButton.title = "NO"
    # ed.content.addSubview(ed.cancelButton)

proc createConfirmDialog*(rect: Rect, question: string, onAnswer:proc(accepted: bool)): EditorConfirmDialog=

    var w = newWindow(rect)

    w.makeLayout:
        -EditorConfirmDialog as dialog:
            origin == super
            size == super

    dialog.question = question
    dialog.acceptButton.onAction do():
        onAnswer(true)
    dialog.cancelButton.onAction do():
        onAnswer(false)

    result = dialog


#    w.addSubView(dialog)
