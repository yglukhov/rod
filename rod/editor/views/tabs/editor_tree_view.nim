import variant, sets, intsets, system, algorithm
import nimx / [ outline_view, text_field, view, button, layout, types, table_view_cell, scroll_view ]
import editor_tab_view
import ../../../../rod/[ node ]
import ../../editor_types

type EditorTreeView* = ref object of EditorTabView
  outlineView: OutlineView
  filterField: TextField
  renameField: TextField

proc onAddNodeClicked(v: EditorTreeView) =
  var sip = v.outlineView.selectedIndexPath
  var n = v.composition.rootNode
  if sip.len == 0:
    sip.add(0)
  else:
    n = v.outlineView.itemAtIndexPath(sip).get(Node)
  if not n.composition.isNil and n != v.composition.rootNode:
    return

  v.outlineView.expandRow(sip)
  discard n.newChild("New Node")
  sip.add(n.children.len - 1)

  # v.onTreeChanged()
  v.outlineView.reloadData()
  # v.outlineView.selectItemAtIndexPath(sip)

proc onRemoveNodeClicked(v: EditorTreeView) =
  echo "remove"

proc onDragAndDrop(v:EditorTreeView, fromIp, toIp: openarray[int]) =
  # echo "drag from", fromIp, " to ", toIp
  let f = v.outlineView.itemAtIndexPath(fromIp).get(Node)
  var tos = @toIp
  tos.setLen(tos.len - 1)
  let t = v.outlineView.itemAtIndexPath(tos).get(Node)
  let toIndex = toIp[^1]
  echo "from ", fromIp, ":", f.name, " to ", toIp, ":", t.name, " toIndex ", toIndex, " isSame parent ", f.parent == t
  if f.parent == t:
    let cIndex = t.children.find(f)
    if toIndex < cIndex:
      t.children.delete(cIndex)
      t.children.insert(f, toIndex)
    elif toIndex > cIndex:
      t.children.delete(cIndex)
      t.children.insert(f, toIndex - 1)
  else:
    f.removeFromParent()
    t.insertChild(f, toIndex)

  v.outlineView.reloadData()

proc initFakeComposition(): CompositionDocument =
  result = new(CompositionDocument)
  result.rootNode = newNode("123")
  result.path = "123.s"

  var root = newNode("root")
  for i in 0..10:
    var n = newNode($i)
    root.addChild(n)

    for q in 0..< i:
      var ch = newNode($q)
      n.addChild(ch)
      n = ch

  result.rootNode.addChild(root)

method init*(v: EditorTreeView) =
  procCall v.EditorTabView.init()
  v.composition = initFakeComposition()

  v.makeLayout:
    x == super.x
    - Button:
      title: "+"
      y == super.y
      height == 20
      width == 20
      x == 1
      onAction:
        try:
          v.onAddNodeClicked()
        except Exception as e:
          echo "can't add ", e.msg, getStackTrace(e)

    - Button:
      title: "-"
      y == super.y
      height == 20
      width == 20
      x == prev.trailing + 1
      onAction:
        try:
          v.onRemoveNodeClicked()
        except Exception as e:
          echo "can't remove ", e.msg, getStackTrace(e)

    - ScrollView:
      frame == inset(super, 2, 22, 2, 2)
      backgroundColor: blackColor()
      - OutlineView as outline:
        backgroundColor: grayColor()
        width == super
        height == super @ WEAK
        defaultRowHeight: 20

        numberOfChildren do(i: Node, indexPath: IndexPath) -> int:
          i.children.len

        rootItem do() -> Node:
          v.composition.rootNode

        childOfItem do(i: Node, indexPath: IndexPath) -> Node:
          i.children[indexPath[^1]]

        createCell do() -> TableViewCell:
          result = newTableViewCell()
          result.makeLayout:
            - Label:
              frame == super

        configureCell do(n: Node, c: TableViewCell):
          let l = Label(c.subviews[0])
          let s = n.name
          l.text = s

        onSelectionChange do():
          discard

        onDragAndDrop do(fromIp, toIp: openarray[int]):
          try:
            v.onDragAndDrop(fromIp, toIp)
          except Exception as e: echo e.msg

    # - View:
    #     backgroundColor: newColor(0.0, 0.7, 0.1, 1.0)
    #     top == prev.bottom
    #     width == super
    #     height == 20

  v.outlineView = outline
  outline.reloadData()