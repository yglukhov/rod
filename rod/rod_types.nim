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
        translation*: Vector3
        rotation*: Quaternion
        scale*: Vector3
        components*: TableRef[string, Component]
        children*: seq[Node3D]
        parent*: Node3D
        name*: string
        animations*: TableRef[string, Animation]
        mViewport*: Viewport

    Node2D* = Node3D
    
    Node* = Node3D

    Component* = ref object of RootObj
        node*: Node3D

    Viewport* = ref object
        mCamera*: Camera
        mRootNode*: Node3D
        view*: View
        numberOfNodesWithBackComposition*: int
        numberOfNodesWithBackCompositionInCurrentFrame*: int
        mActiveFrameBuffer*, mBackupFrameBuffer*: SelfContainedImage
        mScreenFrameBuffer*: GLuint
        tempFramebuffers*: seq[SelfContainedImage]
        # passID
        # renderPath
        # observ
        lightSources*: TableRef[string, LightSource]

    CameraProjection* = enum
        cpOrtho, # Auto
        cpPerspective, # Auto
        cpManual

    Camera* = ref object of Component
        projectionMode*: CameraProjection
        zNear*, zFar*: Coord
        mManualGetProjectionMatrix*: proc(viewportBounds: Rect, mat: var Matrix4)

    LightSource* = ref object of Component
        lightAmbient*: float32
        lightDiffuse*: float32
        lightSpecular*: float32
        lightConstant*: float32
        lightLinear*: float32
        lightQuadratic*: float32
        lightAttenuation*: float32
        
        lightPosInited*: bool
        lightAmbientInited*: bool
        lightDiffuseInited*: bool
        lightSpecularInited*: bool
        lightConstantInited*: bool
        lightLinearInited*: bool
        lightQuadraticInited*: bool
        lightAttenuationInited*: bool

    