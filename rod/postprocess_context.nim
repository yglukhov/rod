import rod_types

import nimx.types
import nimx.image
import nimx.render_to_image
import nimx.portable_gl

import rod.component

export PostprocessContext

proc newPostprocessContext*(): PostprocessContext =
    result.new()
    result.shader = invalidProgram
    result.setupProc = proc(c: Component) = discard
    result.drawProc = proc(c: Component) = discard
