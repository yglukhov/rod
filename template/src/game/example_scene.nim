import rod / [ rod_types, node, component ]
import nimx / animation
import ..  / core / game_scene

type
    ExampleScene* = ref object of GameScene

method assetBundles*(gs: ExampleScene): seq[AssetBundleDescriptor] =
    const assetBundles = @[
        assetBundleDescriptor("example_bundle")
    ]
    result = assetBundles

method onResourcesLoaded*(gs: ExampleScene) =
    var comp = newNodeWithResource("example_bundle/composition2")
    var anim = comp.animationNamed("idle")
    anim.numberOfLoops = -1
    comp.addAnimation(anim)
    gs.rootNode.addChild(comp)
