import rod / [ rod_types, component, viewport, node ]
import nimx / [ animation, animation_runner, window ]

method init*(c: AnimationRunnerComponent) =
    c.runner = newAnimationRunner()

method componentNodeWasAddedToSceneView*(c: AnimationRunnerComponent) =
    c.node.sceneView.addAnimationRunner(c.runner)

method componentNodeWillBeRemovedFromSceneView*(c: AnimationRunnerComponent) =
    c.node.sceneView.removeAnimationRunner(c.runner)

registerComponent(AnimationRunnerComponent)
