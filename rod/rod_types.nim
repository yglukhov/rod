import tables

import nimx.types
import nimx.matrixes
import nimx.animation
import nimx.view
import nimx.image
import nimx.portable_gl

import quaternion
import meta_data

const maxLightsCount* = 8

type
    Node3D* = ref object
        mTranslation*: Vector3
        mRotation*: Quaternion
        mScale*: Vector3
        components*: TableRef[string, Component]
        children*: seq[Node3D]
        parent*: Node3D
        name*: string
        animations*: TableRef[string, Animation]
        mSceneView*: SceneView
        alpha*: Coord
        isDirty*: bool

    Node2D* = Node3D

    Node* = Node3D

    Component* = ref object of RootObj
        node*: Node3D

    PostprocessContext* = ref object
        shader*: ProgramRef
        setupProc*: proc(c: Component)
        drawProc*: proc(c: Component)

    SceneView* = ref object of View
        viewMatrixCached*: Matrix4
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
