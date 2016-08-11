{.deprecated.}

import json
import node
import animation.property_animation
import nimx.animation
proc animationWithAEJson*(n: Node, j: JsonNode): Animation = newPropertyAnimation(n, j)
