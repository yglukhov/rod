import rod.component
import rod.mesh

type MeshComponent* = ref object of Component
    mesh*: Mesh

method draw*(m: MeshComponent) =
    m.mesh.draw()

registerComponent[MeshComponent]()
