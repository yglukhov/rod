import variant, sets, intsets, system, algorithm
import nimx / [ outline_view, text_field, view, button, layout, types, table_view_cell, scroll_view ]
import editor_tab_view
import rod / [ node ]
import ../../editor_types

type EditorTreeView* = ref object of EditorTabView
    outlineView: OutlineView
    filterField: TextField
    renameField: TextField

proc onAddNodeClicked(v: EditorTreeView) =
    var sip: seq[int]
    for e in v.outlineView.selectedRows:
        sip.add(e)

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

method init*(v: EditorTreeView) =
    procCall v.EditorTabView.init()
    v.name = "tree"
    v.composition = new(CompositionDocument)
    v.composition.rootNode = newNode("123")
    v.composition.path = "123.s"

    for i in 0..10:
        v.composition.rootNode.addChild(newNode($i))

    v.makeLayout:
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
            # frame == inset(super, 2, 25, 2, 2)
            y == prev.bottom
            width == super
            bottom <= super
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
                    # Amalyze `c.col` to differentiate between columns
                    result = newTableViewCell()
                    result.makeLayout:
                        - Label:
                            frame == super

                configureCell do(n: Node, c: TableViewCell):
                    # Amalyze `c.col` to differentiate between columns
                    let l = Label(c.subviews[0])
                    let s = n.name
                    l.text = s

                onSelectionChange do():
                    # echo "Selection changed: ", outline.selectedIndexPaths()
                    # v.outlineView.selectedIndexPath = v.outlineView.selectedRows
                    echo "select ", v.outlineView.selectedIndexPath, " rows ", v.outlineView.selectedRows
        - View:
            backgroundColor: newColor(0.0, 0.7, 0.1, 1.0)
            top == prev.bottom
            width == super
            height == 20

    v.outlineView = outline
    outline.reloadData()