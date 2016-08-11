import tables

import nimx.types
import nimx.matrixes
import nimx.animation
import nimx.view
import nimx.image
import nimx.portable_gl

import quaternion

const maxLightsCount* = 8

type
    Node3D* = ref object
        mTranslation*: Vector3
        mRotation*: Quaternion
        mScale*: Vector3
        components*: TableRef[string, Component]
        children*: seq[Node3D]
        mParent*: Node3D
        name*: string
        animations*: TableRef[string, Animation]
        mSceneView*: SceneView
        alpha*: Coord
        mMatrix*: Matrix4
        worldMatrix*: Matrix4
        isDirty*: bool
        layer*: int

    Node2D* = Node3D

    Node* = Node3D

    BBox* = ref object of RootObj
        maxPoint*: Vector3
        minPoint*: Vector3

    Component* = ref object of RootObj
        node*: Node3D
        bbox*: BBox

    PostprocessContext* = ref object
        shader*: ProgramRef
        setupProc*: proc(c: Component)
        drawProc*: proc(c: Component)
        depthImage*: SelfContainedImage
        depthMatrix*: Matrix4

    SceneView* = ref object of View
        viewMatrixCached*: Matrix4
        viewProjMatrix*: Matrix4
        mCamera*: Camera
        mRootNode*: Node3D
        animationRunner*: AnimationRunner
        #view*: View
        numberOfNodesWithBackComposition*: int
        numberOfNodesWithBackCompositionInCurrentFrame*: int
        mActiveFrameBuffer*, mBackupFrameBuffer*: SelfContainedImage
        mScreenFrameBuffer*: FramebufferRef
        tempFramebuffers*: seq[SelfContainedImage]
        lightSources*: TableRef[string, LightSource]
        uiComponents*: seq[UIComponent]
        postprocessContext*: PostprocessContext

    Viewport* {.deprecated.} = SceneView

    CameraProjection* = enum
        cpOrtho, # Auto
        cpPerspective, # Auto
        cpManual

    Camera* = ref object of Component
        projectionMode*: CameraProjection
        zNear*, zFar*, fov*: Coord
        mManualGetProjectionMatrix*: proc(viewportBounds: Rect, mat: var Matrix4)
        viewportSize*: Size

    UIComponent* = ref object of Component
        mView*: View

    LightSource* = ref object of Component
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

    Particle* = ref object
        node*: Node
        position*: Vector3
        rotation*, rotationVelocity*: Vector3 #deg per sec
        scale*: Vector3
        lifetime*: float
        normalizedLifeTime*: float
        color*: Color
        velocity*: Vector3
        randStartScale*: float
