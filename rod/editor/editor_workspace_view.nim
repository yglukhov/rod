import math, algorithm, strutils, tables, json, logging, ospaths

import nimx / [ view, toolbar, editor / tab_view, linear_layout, button,
    font, popup_button, window, menu, notification_center, mini_profiler,
    color_picker, view_event_handling ]

import rod / [ rod_types, node ]
import rod / editor / [ editor_types, editor_tab_registry ]

when loadingAndSavingAvailable:
    import rod.editor.editor_open_project_view
    import os

proc createWorkspaceLayout*(window: Window, editor: Editor): WorkspaceView
proc onTabSlit(w: WorkspaceView, tv: TabView)=
    var i = w.tabViews.find(tv)
    if i < 0:
        w.tabViews.add(tv)
        echo "newTabView added "

    echo "onTabSlit ", w.tabViews.len

proc onTabRemove(w: WorkspaceView, tv: TabView)=
    var i = w.tabViews.find(tv)
    if i >= 0:
        w.tabViews.delete(i)
        echo "tabView removed!"
    echo "onTabRemove ", w.tabViews.len

proc selectTab*(w: WorkspaceView, tb: EditorTabView)=
    for tv in w.tabViews:
        var i = tv.tabIndex(tb)
        if i >= 0:
            tv.selectTab(i)
            return

proc setTabTitle*(w: WorkspaceView, tb: EditorTabView, title: string)=
    for tv in w.tabViews:
        var i = tv.tabIndex(tb)
        if i >= 0:
            tv.setTitleOfTab(title, i)
            return

proc newToolbarButton*(w: WorkspaceView, title: string): Button =
    let f = systemFont()
    let width = f.sizeOfString(title).width
    result = Button.new(newRect(0, 0, width + 20, 20))
    result.title = title
    w.toolbar.addSubview(result)

proc addToolbarMenu*(w: WorkspaceView, item: MenuItem) =
    let b = w.newToolbarButton(item.title)
    b.onAction() do():
        item.popupAtPoint(b, newPoint(0, 25))
# proc getTabViews(tv: View): seq[TabView] =
#     result = @[]
#     if tv of TabView:
#         result.add(tv.TabView)
#     for sv in tv.subviews:
#         result.add(sv.getTabViews())

proc newTabView(w: WorkspaceView): TabView =
    result = TabView.new(newRect(0,0,100,100))
    result.dockingTabs = true
    result.userConfigurable = true
    let r = result
    r.onSplit = proc(v: TabView)=
        w.onTabSlit(v)

    r.onRemove = proc(v: TabView)=
        w.onTabRemove(v)

    r.onClose = proc(v: View)=
        if v of EditorTabView:
            let et = v.EditorTabView
            for i, t in w.tabs:
                if t == et:
                    w.tabs.del(i)
                    return

            for i, t in w.compositionEditors:
                if t == et:
                    w.compositionEditors.del(i)
                    return

    w.tabViews.add(r)

proc addTab*(w: WorkspaceView, tb: EditorTabView)=
    var anchor = tb.tabAnchor()
    var size = tb.tabSize(w.frame)
    var anchorView = w.anchors[anchor.int]
    if anchorView.isNil or anchorView.tabsCount == 0:
        var tb = w.newTabView()
        anchorView = tb
        let horl = w.horizontalLayout
        let verl = w.verticalLayout
        case anchor:
        of etaLeft:
            let dps = horl.dividerPositions()
            horl.insertSubview(anchorView, 0)
            horl.setDividerPosition(size.width, 0)
            if dps.len > 0:
                horl.setDividerPosition(dps[0], dps.len)

        of etaRight:
            horl.addSubview(anchorView)
            let dps = horl.dividerPositions().len
            if dps > 0:
                horl.setDividerPosition(w.frame.width - size.width, dps - 1)
        of etaBottom:
            verl.addSubview(anchorView)
            verl.setDividerPosition(w.frame.height - size.height, 0)
        else:
            let dps = horl.dividerPositions()
            horl.insertSubview(anchorView, clamp(dps.len div 2, 0, dps.len))
        w.anchors[anchor.int] = anchorView

    anchorView.addTab(tb.name, tb)

proc createCompositionEditor*(w: WorkspaceView, c: CompositionDocument = nil): EditorTabView=
    var rt: EditViewEntry
    var found = false
    for t in registeredEditorTabs():
        if t.name == RodInternalTab & "/Scene":
            rt = t
            found = true
            break

    if not found:
        warn "Can't create ", RodInternalTab & "/Scene", " tab!"
        return

    var tabView = rt.create().EditorTabView
    tabView.editor = w.editor
    var comp: CompositionDocument
    if not c.isNil:
        var compRoot = c.rootNode

        try:
            when loadingAndSavingAvailable:
                if compRoot.isNil:
                    compRoot = newNodeWithUrl("file://"&c.path)
                    c.rootNode = compRoot

        except:
            error "Exception caught: ", getCurrentExceptionMsg()
            error "stack trace: ", getCurrentException().getStackTrace()

        if compRoot.isNil:
            error "rootNode isNil: ", getStackTrace()
            return nil

        tabview.rootNode = compRoot
        tabView.name = splitFile(c.path).name
        comp = c
    else:
        tabView.name = "new composition"
        comp = new(CompositionDocument)
        comp.rootNode = newNode("new composition")
        tabView.rootNode = comp.rootNode

    comp.owner = tabView

    let frame = w.bounds
    var size = tabview.tabSize(frame)

    tabview.composition = comp
    tabview.init(newRect(newPoint(0.0, 0.0), size))
    w.compositionEditors.add(tabView)

    result = tabView

# proc closeCompositionEditor*(w: WorkspaceView, c: CompositionDocument)=
#     for i, t in w.compositionEditors:
#         if t.composition == c:
#             t.removeFromSplitViewSystem()
#             t.removeFromSuperview()
#             w.compositionEditors.del(i)
#             break


proc createViewMenu(w: WorkspaceView) =
    let m = makeMenu("View"):
        # - "Zoom on Selection":
        #     if not w.editor.selectedNode.isNil:
        #         let cam = w.editor.rootNode.findNode("camera")
        #         if not cam.isNil:
        #             w.editor.rootNode.findNode("camera").focusOnNode(w.editor.selectedNode)
        # - "-"
        # - "2D":
        #     let cam = w.editor.currentCamera()
        #     if not cam.isNil: cam.projectionMode = cpOrtho
        # - "3D":
        #     let cam = w.editor.currentCamera()
        #     if not cam.isNil: cam.projectionMode = cpPerspective
        - "Profiler":
            sharedProfiler().enabled = not sharedProfiler().enabled

    w.addToolbarMenu(m)

when loadingAndSavingAvailable:
    proc createProjectMenu(w: WorkspaceView) =
        let m = makeMenu("Project"):
            - "Open":
                var openProj = new(EditorOpenProjectView)
                openProj.init(w.bounds)
                w.addSubview(openProj)

                openProj.onOpen = proc(p: EditorProject)=
                    openProj.removeFromSuperview()
                    w.editor.currentProject = p
                    w.removeFromSuperview()
                    w.editor.workspaceView = createWorkspaceLayout(w.editor.window, w.editor)
                    echo "try open project ", p

                openProj.onClose = proc()=
                    openProj.removeFromSuperview()

            - "Save":
                if w.editor.currentProject.path.len == 0:
                    echo "not saved project"

                w.editor.currentProject.tabs = @[]
                for t in w.tabs:
                    w.editor.currentProject.tabs.add((name:t.name, frame: zeroRect))
                w.editor.currentProject.saveProject()

        w.addToolbarMenu(m)

proc createChangeBackgroundColorButton(w: WorkspaceView) =
    var cPicker: ColorPickerView
    let b = w.newToolbarButton("Background Color")
    b.onAction do():
        if cPicker.isNil:
            cPicker = newColorPickerView(newRect(0, 0, 300, 200))
            cPicker.onColorSelected = proc(c: Color) =
                w.editor.sceneView.backgroundColor = c
            let popupPoint = b.convertPointToWindow(newPoint(0, b.bounds.height + 5))
            cPicker.setFrameOrigin(popupPoint)
            b.window.addSubview(cPicker)
        else:
            cPicker.removeFromSuperview()
            cPicker = nil

proc toggleEditTab(w: WorkspaceView, tab:EditViewEntry): proc() =
    result = proc() =
        var tabindex = -1
        var tabview: EditorTabView
        for i, t in w.tabs:
            if t.name == tab.name:
                tabindex = i
                tabview = t
                break

        let frame = w.bounds
        if tabindex >= 0:
            var anchorView: TabView
            var anchorIndex = -1
            for i, av in w.tabViews:
                if av.tabIndex(tab.name) >= 0:
                    anchorIndex = i
                    anchorView = av
                    break

            if not anchorView.isNil:
                let edtabi = anchorView.tabIndex(tab.name)
                if edtabi >= 0:
                    anchorView.removeTab(edtabi)
                    if anchorView.tabsCount == 0:
                        w.onTabRemove(anchorView)
                        anchorView.removeFromSplitViewSystem()

            w.tabs.delete(tabindex)
        else:
            tabview = tab.create().EditorTabView
            tabview.editor = w.editor

            var size = tabview.tabSize(frame)
            tabview.rootNode = w.editor.rootNode

            tabview.init(newRect(newPoint(0.0, 0.0), size))
            tabview.setEditedNode(w.editor.selectedNode)

            w.addTab(tabview)
            w.tabs.add(tabview)

proc createTabView(w: WorkspaceView)=
    var toolBarMenus = newSeq[MenuItem]()
    var defMenu = newMenuItem("Tabs")
    defMenu.children = @[]
    toolBarMenus.add(defMenu)

    for rv in registeredEditorTabs():
        var spname = rv.name.split("/")
        if spname.len > 1:
            if spname[0] != RodInternalTab:
                var parentMenu: MenuItem
                var levelMenus = toolBarMenus
                for pi in 0 ..< spname.len:
                    var cm: MenuItem
                    for m in levelMenus:
                        if m.title == spname[pi]:
                            levelMenus = m.children
                            cm = m
                            break

                    if cm.isNil:
                        cm = newMenuItem(spname[pi])
                        if pi == spname.len - 1:
                            cm.action = w.toggleEditTab(rv)
                        else:
                            if pi == 0:
                                toolBarMenus.add(cm)
                            cm.children = @[]

                        if not parentMenu.isNil:
                            parentMenu.children.add(cm)

                    parentMenu = cm
                    levelMenus = cm.children
        else:
            var rmi = newMenuItem(rv.name)
            rmi.action = w.toggleEditTab(rv)
            defMenu.children.add(rmi)

    for m in toolBarMenus:
        w.addToolbarMenu(m)

proc createSceneMenu(w: WorkspaceView) =
    when loadingAndSavingAvailable:
        if w.editor.startFromGame:
            let m = makeMenu("Scene"):
                - "Load":
                    w.editor.notifCenter.postNotification(RodEditorNotif_onNodeLoad)

                - "Save":
                    w.editor.notifCenter.postNotification(RodEditorNotif_onNodeSave)

            w.addToolbarMenu(m)
        else:
            let m = makeMenu("Scene"):
                - "New":
                    w.editor.notifCenter.postNotification(RodEditorNotif_onCompositionNew)
                    var sceneEdit = w.createCompositionEditor()
                    if not sceneEdit.isNil:
                        w.addTab(sceneEdit)
                - "Load comp":
                    w.editor.notifCenter.postNotification(RodEditorNotif_onCompositionOpen)
                    # e.loadNode()
                - "Save comp":
                    w.editor.notifCenter.postNotification(RodEditorNotif_onCompositionSave)

                - "Save comp as ...":
                    w.editor.notifCenter.postNotification(RodEditorNotif_onCompositionSaveAs)

                - "Load node":
                    w.editor.notifCenter.postNotification(RodEditorNotif_onNodeLoad)

                - "Save node":
                    w.editor.notifCenter.postNotification(RodEditorNotif_onNodeSave)
                    # if not e.selectedNode.isNil:
                    #     e.saveNode(e.selectedNode)
            w.addToolbarMenu(m)

proc createWorkspaceLayout*(window: Window, editor: Editor): WorkspaceView =
    let w = WorkspaceView.new(window.bounds)
    w.editor = editor
    w.tabs = @[]
    # e.workspaceView = v
    w.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}
    w.compositionEditors = @[]
    w.tabViews = @[]


    w.toolbar = Toolbar.new(newRect(0, 0, 20, toolbarHeight))
    w.toolbar.userResizeable = false

    w.verticalLayout = newVerticalLayout(newRect(0, toolbarHeight, w.bounds.width, w.bounds.height - toolbarHeight))
    w.verticalLayout.userResizeable = true
    w.horizontalLayout = newHorizontalLayout(newRect(0, 0, 800, 200))
    w.horizontalLayout.userResizeable = true
    w.horizontalLayout.resizingMask = "wh"
    w.verticalLayout.resizingMask = "wh"

    w.addSubview(w.toolbar)

    w.verticalLayout.addSubview(w.horizontalLayout)
    w.addSubview(w.verticalLayout)

    when loadingAndSavingAvailable:
        w.createProjectMenu()

    if w.editor.startFromGame and not w.editor.rootNode.isNil:
        let rootEditorView = w.editor.sceneView.superview
        rootEditorView.replaceSubview(w.editor.sceneView, w)

        var comp = new(CompositionDocument)
        comp.rootNode = w.editor.rootNode

        var compTab = w.createCompositionEditor(comp)
        if not compTab.isNil:
            w.addTab(compTab)
        w.editor.mCurrentComposition = comp
    else:
        var compTab = w.createCompositionEditor()
        if not compTab.isNil:
            w.addTab(compTab)
            w.editor.rootNode = compTab.rootNode

        window.addSubview(w)
        w.editor.mCurrentComposition = compTab.composition

    if w.editor.currentProject.tabs.isNil:
        for rt in registeredEditorTabs():
            if rt.name in defaultTabs:
                w.toggleEditTab(rt)()
    else:
        for rt in registeredEditorTabs():
            for st in w.editor.currentProject.tabs:
                if st.name == rt.name:
                    w.toggleEditTab(rt)()
                    break

    w.createSceneMenu()
    w.createViewMenu()
    w.createTabView()
    w.newToolbarButton("GameInput").onAction do():
        w.editor.sceneInput = not w.editor.sceneInput
    w.createChangeBackgroundColorButton()
    result = w

method onKeyDown(v: WorkspaceView, e: var Event): bool =
    if not v.onKeyDown.isNil:
        result = v.onKeyDown(e)
