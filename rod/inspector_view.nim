import strutils, tables
import nimx.view
import nimx.text_field
import nimx.button
import nimx.matrixes
import nimx.menu
import variant

export view

import panel_view
import node
import component
import quaternion
import property_visitor
import numeric_text_field
import rod_types

type InspectorView* = ref object of PanelView
    #node: Node3D
    nameTextField: TextField

method init*(i: InspectorView, r: Rect) =
    procCall i.PanelView.init(r)
    let title = newLabel(newRect(2, 2, 100, 15))
    title.text = "Inspector"
    i.addSubview(title)

proc newTextPropertyView(y: Coord, propName: string, setter: proc(s: string), getter: proc(): string): View =
    result = View.new(newRect(0, y, 200, 17))
    let v = newLabel(newRect(0, 0, 100, 15))
    v.text = propName & ":"
    result.addSubview(v)
    var x = 70.Coord
    let textField = newTextField(newRect(x, 0, result.bounds.width - x, result.bounds.height))
    textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    textField.text = getter()
    textField.onAction do():
        setter(textField.text)
    result.addSubview(textField)

proc newCoordPropertyView(y: Coord, propName: string, setter: proc(s: Coord), getter: proc(): Coord): View =
    result = View.new(newRect(0, y, 200, 17))
    let v = newLabel(newRect(0, 0, 100, 15))
    v.text = propName & ":"
    result.addSubview(v)
    var x = 70.Coord
    let textField = newNumericTextField(newRect(x, 0, result.bounds.width - x, result.bounds.height))
    textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    textField.text = formatFloat(getter(), ffDecimal, 3)
    textField.onAction do():
        setter(textField.text.parseFloat())
    result.addSubview(textField)

proc newColorPropertyView(y: Coord, propName: string, setter: proc(s: Color), getter: proc(): Color): View =
    result = View.new(newRect(0, y, 200, 17))
    let v = newLabel(newRect(0, 0, 100, 15))
    v.text = propName & ":"
    result.addSubview(v)

    const vecLen = 3 + 1

    let colorView = View.new(newRect(70, 0, 17, 17))
    colorView.backgroundColor = getter()
    result.addSubview(colorView)

    var x = 88.Coord
    let width = (result.bounds.width - x) / vecLen

    let pv = result
    proc complexSetter() =
        let c = newColor(
            TextField(pv.subviews[2]).text.parseFloat(),
            TextField(pv.subviews[3]).text.parseFloat(),
            TextField(pv.subviews[4]).text.parseFloat(),
            TextField(pv.subviews[5]).text.parseFloat(),
            )
        setter(c)
        colorView.backgroundColor = c

    template toVector(c: Color): Vector4 = newVector4(c.r, c.g, c.b, c.a)

    for i in 0 ..< vecLen:
        let textField = newNumericTextField(newRect(x, 0, width, result.bounds.height))
        x += width
        if i == vecLen - 1:
            textField.autoresizingMask = {afFlexibleMaxX, afFlexibleMaxY}
        else:
            textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        textField.text = formatFloat(getter().toVector[i], ffDecimal, 3)
        textField.onAction complexSetter
        result.addSubview(textField)

proc newVecPropertyView[T](y: Coord, propName: string, setter: proc(s: T), getter: proc(): T): View =
    result = View.new(newRect(0, y, 200, 17))
    let v = newLabel(newRect(0, 0, 100, 15))
    v.text = propName & ":"
    result.addSubview(v)

    const vecLen = high(T) + 1

    var x = 70.Coord
    let width = (result.bounds.width - x) / vecLen

    let pv = result
    proc complexSetter() =
        var val : TVector[vecLen, Coord]
        for i in 1 ..< pv.subviews.len:
            val[i - 1] = TextField(pv.subviews[i]).text.parseFloat()
        setter(val)

    for i in 0 ..< vecLen:
        let textField = newNumericTextField(newRect(x, 0, width, result.bounds.height))
        x += width
        if i == vecLen - 1:
            textField.autoresizingMask = {afFlexibleMaxX, afFlexibleMaxY}
        else:
            textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        textField.text = formatFloat(getter()[i], ffDecimal, 3)
        textField.onAction complexSetter
        result.addSubview(textField)

proc newUnknownPropertyView(y: Coord, name: string): View =
    result = View.new(newRect(0, y, 200, 17))
    let v = newLabel(newRect(0, 0, 100, 15))
    v.text = name & " - unknown property"
    result.addSubview(v)

proc newSectionTitle(y: Coord, inspector: InspectorView, n: Node3D, name: string): View
proc createNewComponentButton(y: Coord, inspector: InspectorView, n: Node3D): View

proc `inspectedNode=`*(i: InspectorView, n: Node3D) =
    #i.node = n
    if i.subviews.len > 1:
        i.subviews[1].removeFromSuperview()
    if not n.isNil:
        let propView = View.new(newRect(0, 17, i.bounds.width, i.bounds.height - 17))
        propView.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}

        var y = Coord(0)
        var pv = newTextPropertyView(y, "name", proc(s: string) = n.name = s, proc(): string = n.name)
        y += pv.frame.height
        propView.addSubview(pv)
        pv = newVecPropertyView(y, "translation", proc(s: Vector3) = n.translation = s, proc(): Vector3 = n.translation)
        y += pv.frame.height
        propView.addSubview(pv)
        pv = newVecPropertyView(y, "scale", proc(s: Vector3) = n.scale = s, proc(): Vector3 = n.scale)
        y += pv.frame.height
        propView.addSubview(pv)
        pv = newVecPropertyView(y, "rotation", proc(s: Vector3) = n.rotation = newQuaternionFromEulerZXY(s[0], s[1], s[2]), proc(): Vector3 = n.rotation.eulerAngles())
        y += pv.frame.height
        propView.addSubview(pv)
        pv = newCoordPropertyView(y, "alpha", proc(a: Coord) = n.alpha = a, proc(): Coord = n.alpha)
        y += pv.frame.height
        propView.addSubview(pv)

        if not n.components.isNil:
            for k, v in n.components:
                pv = newSectionTitle(y, i, n, k)
                y += pv.frame.height
                propView.addSubview(pv)

                var visitor : PropertyVisitor
                visitor.requireName = true
                visitor.requireSetter = true
                visitor.requireGetter = true
                visitor.commit = proc() =
                    variantMatch case visitor.setterAndGetter as sng
                    of SetterAndGetter[Coord]:
                        pv = newCoordPropertyView(y, visitor.name, sng.setter, sng.getter)
                    of SetterAndGetter[Vector2]:
                        pv = newVecPropertyView(y, visitor.name, sng.setter, sng.getter)
                    of SetterAndGetter[Vector3]:
                        pv = newVecPropertyView(y, visitor.name, sng.setter, sng.getter)
                    of SetterAndGetter[Vector4]:
                        pv = newVecPropertyView(y, visitor.name, sng.setter, sng.getter)
                    of SetterAndGetter[Color]:
                        pv = newColorPropertyView(y, visitor.name, sng.setter, sng.getter)
                    else:
                        pv = newUnknownPropertyView(y, visitor.name)
                    y += pv.frame.height
                    propView.addSubview(pv)
                v.visitProperties(visitor)

        pv = createNewComponentButton(y, i, n)
        y += pv.frame.height
        propView.addSubview(pv)

        var fs = propView.frame.size
        fs.height = y
        propView.setFrameSize(fs)
        i.addSubview(propView)

proc newSectionTitle(y: Coord, inspector: InspectorView, n: Node3D, name: string): View =
    result = View.new(newRect(0, y, 200, 17))
    let v = newLabel(newRect(5, 0, 100, 15))
    v.text = name
    result.addSubview(v)

    let removeButton = newButton(newRect(result.bounds.width - 20, 0, 20, 17))
    removeButton.autoresizingMask = {afFlexibleMinX, afFlexibleMaxY}
    removeButton.title = "-"
    removeButton.onAction do():
        n.removeComponent(name)
        inspector.inspectedNode = n
    result.addSubview(removeButton)

proc createNewComponentButton(y: Coord, inspector: InspectorView, n: Node3D): View =
    let b = Button.new(newRect(0, y, 120, 20))
    b.title = "New component"
    b.onAction do():
        var menu : Menu
        menu.new()
        var items = newSeq[MenuItem]()
        for i, c in registeredComponents():
            let menuItem = newMenuItem(c)
            let pWorkaroundForJS = proc(i: int): proc() =
                result = proc() =
                    discard n.component(menuItem.title)
                    inspector.inspectedNode = n

            menuItem.action = pWorkaroundForJS(i)
            items.add(menuItem)

        menu.items = items
        menu.popupAtPoint(b, newPoint(0, b.bounds.height))
    result = b
