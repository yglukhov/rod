import nimx.matrixes
import nimx.types
import nimx.animation

import rod_types
import nimasset.collada

proc animationWithCollada*(node: Node, anim: ColladaAnimation) =
    ## Attach animation to node
