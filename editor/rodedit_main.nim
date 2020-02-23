import tables, logging, strutils, macros

import nimx / [ matrixes, image, window, autotest ]
import rod / [ viewport, edit_view, node,component, scene_composition ]
import rod/editor/editor_error_handling
import rod/component/[camera, solid, mesh_component, material, light, sprite]

import rod/editor/editor_project_settings

const rodPluginFile {.strdefine.} = ""
when rodPluginFile.len != 0:
    macro doImport(): untyped =
        newTree(nnkImportStmt, newLit(rodPluginFile))
    doImport()

when loadingAndSavingAvailable:
    import os
    import rod/editor/editor_open_project_view

const isMobile = defined(ios) or defined(android)

proc runAutoTestsIfNeeded() =
    uiTest generalUITest:
        discard
        quitApplication()

    registerTest(generalUITest)
    when defined(runAutoTests):
        startRegisteredTests()

proc switchToEditView(w: Window, proj: EditorProject)=
    discard w.startEditorForProject(proj)

proc startApplication() =
    when isMobile or defined(js):
        var mainWindow = newFullscreenWindow()
    else:
        var mainWindow = newWindow(newRect(40, 40, 1200, 600))
    when loadingAndSavingAvailable:
        var settings = getEditorSettings()
        if settings.lastProject.len > 0:
            when defined(rodedit):
                var proj: EditorProject
                proj.name = "rodedit"
                proj.path = getAppDir()
            else:
                var proj = getProjectAtPath(settings.lastProject)
            mainWindow.title = "Project " & proj.name
            mainWindow.switchToEditView(proj)
        else:
            var openProjView = new(EditorOpenProjectView)
            openProjView.init(mainWindow.bounds)
            mainWindow.addSubView(openProjView)

            openProjView.onOpen = proc(p: EditorProject) =
                openProjView.removeFromSuperview()
                mainWindow.title = "Project " & p.name
                mainWindow.switchToEditView(p)
    else:
        var proj: EditorProject
        mainWindow.title = "Rod"
        mainWindow.switchToEditView(proj)

    runAutoTestsIfNeeded()

when not defined(js):
    onUnhandledException = proc(msg: string) =
        var msg = msg.indent(8)
        error "Exception caught:\n ", msg

runApplication:
    startApplication()
