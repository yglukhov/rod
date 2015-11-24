import nimx.view
import nimx.text_field
export view

import panel_view
import node

type InspectorView* = ref object of PanelView
    node: Node3D
    nameTextField: TextField

method init*(i: InspectorView, r: Rect) =
    procCall i.PanelView.init(r)
    let title = newLabel(newRect(2, 2, 100, 15))
    title.text = "Inspector"

    var v = newLabel(newRect(2, 17, 100, 15))
    v.text = "Name: "
    i.addSubview(v)
    i.nameTextField = newTextField(newRect(102, 17, 100, 15))
    i.addSubview(i.nameTextField)

    i.nameTextField.onAction do():
        if not i.node.isNil:
            i.node.name = i.nameTextField.text

    i.addSubview(title)

proc `inspectedNode=`*(i: InspectorView, n: Node3D) =
    i.node = n
    if i.node.isNil:
        i.nameTextField.text = ""
    else:
        i.nameTextField.text = i.node.name
