import rod_types

import nimx.types
import nimx.image
import nimx.render_to_image
import nimx.portable_gl

export PostprocessContext

proc newPostprocessContext*(): PostprocessContext =
    result.new()
    result.shader = invalidProgram
    result.setupProc = proc() = discard
    result.drawProc = proc() = discard

proc draw*(pc: PostprocessContext) =
    pc.drawProc()
