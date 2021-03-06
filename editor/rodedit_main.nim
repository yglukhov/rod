import tables, logging, strutils

import nimx / [ matrixes, window, autotest ]
import rod / [ edit_view ]
import rod/editor/editor_error_handling
import rod/component/all_components

import rod/editor/editor_project_settings

const rodPluginFile {.strdefine.} = ""
when rodPluginFile.len != 0:
    import macros
    macro doImport(): untyped =
        newTree(nnkImportStmt, newLit(rodPluginFile))
    doImport()

when defined(rodedit):
    import os

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
        var mainWindow = newWindow(newRect(140, 40, 1600, 1000))
    when loadingAndSavingAvailable:
        when defined(rodedit):
            var proj: EditorProject
            proj.name = getAppDir().lastPathPart
            proj.path = getAppDir()
            mainWindow.title = "Project " & proj.name
            mainWindow.switchToEditView(proj)
    else:
        var proj: EditorProject
        mainWindow.title = "Rod"
        mainWindow.switchToEditView(proj)

    runAutoTestsIfNeeded()

when defined(rodedit):
    onUnhandledException = proc(msg: string) =
        var msg = msg.indent(8)
        error "Exception caught:\n ", msg

runApplication:
    startApplication()
