import nimx.view
import nimx.app
import nimx.scroll_view
import nimx.table_view
import nimx.text_field
import nimx.autotest
import nimx.window
import src.game_scene

const isMobile = defined(ios) or defined(android)

let wndRect = newRect(40, 40, 1280, 720)
proc startApplication() =
    var mainWindow : Window

    when isMobile:
        mainWindow = newFullscreenWindow()
    else:
        mainWindow = newWindow(wndRect)

    mainWindow.title = "Template"

    let gs = new(GameScene)
    gs.init(mainWindow.bounds)
    gs.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    mainWindow.addSubview(gs)

    gs.setFrame(mainWindow.bounds)
    gs.resizeSubviews(mainWindow.bounds.size)

runApplication:
    startApplication()
