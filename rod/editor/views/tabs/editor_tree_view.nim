import variant, sets, intsets, system, algorithm
import nimx / [ outline_view, text_field, view, button, layout, types, table_view_cell, scroll_view ]
import ../../../../rod/[ node ]
import ../../editor_view_types

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

  var msg = EditorMessageAddNode.new()
  msg.parentPath = sip[1..^1]
  msg.nodeName = "node"
  v.commandsQueue.post(msg)

proc onRemoveNodeClicked(v: EditorTreeView) =
  var sip = v.outlineView.selectedIndexPath
  if sip.len == 0:
    return

  var msg = EditoMessageRemoveNode(path: sip[1..^1])
  v.commandsQueue.post(msg)

proc onDragAndDrop(v:EditorTreeView, fromIp, toIp: openarray[int]) =
  var msg = EditorMessageReparentNode(fromPath: fromIp[1..^1], toPath: toIp[1..^1])
  v.commandsQueue.post(msg)

proc onSelectionChanged(v: EditorTreeView) =
  if v.outlineView.selectedIndexPath.len == 0:
    return
  var msg = EditorMessageNodeSelectionChanged(path: v.outlineView.selectedIndexPath[1..^1])
  v.commandsQueue.post(msg)

method init*(v: EditorTreeView) =
  procCall v.EditorTabView.init()

  v.makeLayout:
    x == super.x
    - Button:
      title: "+"
      y == super.y
      height == 20
      width == 20
      x == 1
      onAction:
        sandbox:
          v.onAddNodeClicked()

    - Button:
      title: "-"
      y == super.y
      height == 20
      width == 20
      x == prev.trailing + 1
      onAction:
        sandbox:
          v.onRemoveNodeClicked()

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
          sandbox:
            v.onSelectionChanged()

        onDragAndDrop do(fromIp, toIp: openarray[int]):
          sandbox:
            v.onDragAndDrop(fromIp, toIp)

  v.outlineView = outline

method onCompositionChanged*(v: EditorTreeView, c: CompositionDocument) =
  procCall v.EditorTabView.onCompositionChanged(c)
  v.outlineView.reloadData()

method onEditorEvent*(v: EditorTreeView, ev: EditorAPIEvent) =
  if ev.kind == EditorTreeChangedEvent.toEditorMessageId:
    echo "tree changed"
    v.outlineView.reloadData()
