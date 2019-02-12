import nimx/[types, image, render_to_image, portable_gl]
import rod/component
import rod_types

export PostprocessContext

proc newPostprocessContext*(): PostprocessContext =
    result.new()
    result.shader = invalidProgram
    result.setupProc = proc(c: Component) = discard
    result.drawProc = proc(c: Component) = discard
