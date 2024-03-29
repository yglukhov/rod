import nimx / [ types, matrixes, animation, view, image, portable_gl ]
import rod / message_queue
import quaternion
import tables
const maxLightsCount* = 8

when defined(rodedit):
    import json

type
    NodeFlags* = enum # Don't change the order!
        enabled
        affectsChildren # Should posteffects affect only this node or its children as well
        dirty
        serializable

    Node* = ref object
        mTranslation*: Vector3
        mRotation*: Quaternion
        mScale*: Vector3
        renderComponents*: seq[RenderComponent]
        scriptComponents*: seq[ScriptComponent]
        children*: seq[Node]
        mParent*: Node
        name*: string
        animations*: TableRef[string, Animation]
        mSceneView*: SceneView
        mMatrix*: Matrix4
        worldMatrix*: Matrix4
        alpha*: Coord
        composition*: Composition
        mAnchorPoint*: Vector3
        mFlags*: set[NodeFlags]

        when defined(rodedit):
            jAnimations*: JsonNode

    BBox* = object
        minPoint*: Vector3
        maxPoint*: Vector3

    Frustum* = BBox

    Component* = ref object of RootRef
        node*: Node

    ScriptComponent* = ref object of Component
    RenderComponent* = ref object of Component

    AnimationRunnerComponent* = ref object of ScriptComponent
        runner*: AnimationRunner

    PostprocessContext* = ref object
        shader*: ProgramRef
        setupProc*: proc(c: Component)
        drawProc*: proc(c: Component)
        depthImage*: SelfContainedImage
        depthMatrix*: Matrix4

    System* = ref object of RootRef
        sceneView*: SceneView

    SceneView* = ref object of View
        systems*: seq[System]
        viewMatrixCached*: Matrix4
        viewProjMatrix*: Matrix4
        mCamera*: Camera
        mRootNode*: Node
        animationRunners*: seq[AnimationRunner]
        lightSources*: TableRef[string, LightSource]
        uiComponents*: seq[UIComponent]
        postprocessContext*: PostprocessContext
        editing*: bool
        afterDrawProc*: proc() {.gcsafe.} # PRIVATE DO NOT USE!!!

    Composition* = ref object
        url*: string
        node*: Node
        when defined(rodedit):
            originalUrl*: string # used in editor to restore url

    CameraProjection* = enum
        cpOrtho,
        cpPerspective

    Camera* = ref object of ScriptComponent
        projectionMode*: CameraProjection
        zNear*, zFar*, fov*: Coord
        viewportSize*: Size

    UIComponent* = ref object of RenderComponent
        mView*: View
        mEnabled*: bool

    LightSource* = ref object of ScriptComponent
        mLightAmbient*: float32
        mLightDiffuse*: float32
        mLightSpecular*: float32
        mLightConstant*: float32
        mLightLinear*: float32
        mLightQuadratic*: float32
        mLightAttenuation*: float32

        mLightColor*: Color

        lightPosInited*: bool
        lightAmbientInited*: bool
        lightDiffuseInited*: bool
        lightSpecularInited*: bool
        lightConstantInited*: bool
        lightLinearInited*: bool
        lightQuadraticInited*: bool
        mLightAttenuationInited*: bool
