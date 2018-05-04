import nimx / [view, menu, types]

import rod / [ node, edit_view ]

import editor_types

proc selectNode(t: EditorTabView, n: Node) = 
    t.editor.sceneTreeDidChange()
    t.editor.selectedNode = n

proc showSceneContextMenu*(inTab: EditorTabView, pos: Point)=
    let m = newMenuItem(inTab.name)
    m.items = @[]

    if not inTab.composition.isNil:
        var selNode = inTab.composition.selectedNode

        var addnode = newMenuItem("Add node")
        addnode.action = proc()=
            var n: Node
            if selNode.isNil:
                n = inTab.composition.rootNode.newChild("new node")
            else:
                n = selNode.newChild("new node")
            inTab.selectNode(n)
            
        m.items.add(addnode)

        if not selNode.isNil:
            var children = newMenuItem("Children")
            children.items = @[]

            let cb = proc(n: Node): proc()=
                let node = n
                result = proc() =
                    inTab.selectNode(node)

            for ch in selNode.children:
                var item = newMenuItem(ch.name)
                item.action = cb(ch)
                children.items.add(item)

            m.items.add(children)
    
        var selParent = newMenuItem("Select parent")
        selParent.action = proc()=
            if not selNode.isNil and not selNode.parent.isNil:
                inTab.selectNode(selNode.parent)
        m.items.add(selParent)
    
    m.popupAtPoint(inTab, pos)

