import nimx.portable_gl

type VertexDataInfo* = ref object of RootObj
    numOfCoordPerVert*: GLint
    numOfCoordPerNormal*: GLint
    numOfCoordPerTexCoord*: GLint
    numOfCoordPerBinormal*: GLint
    numOfCoordPerTangent*: GLint
    stride*: int

proc newVertexInfoWithZeroParams*(): VertexDataInfo = 
    result.new()

proc newVertexInfoWithVertexData*(vertexDataLen = 0, texCoordDataLen = 0, normalDataLen = 0, binormalDataLen = 0, tangentDataLen: int = 0): VertexDataInfo = 
    result.new()
    if vertexDataLen != 0:
        result.numOfCoordPerVert = 3
    if texCoordDataLen != 0:
        result.numOfCoordPerTexCoord = 2
    if normalDataLen != 0:
        result.numOfCoordPerNormal = 3
    if binormalDataLen != 0:
        result.numOfCoordPerBinormal = 3
    if tangentDataLen != 0:
        result.numOfCoordPerTangent = 3
    result.stride = (result.numOfCoordPerVert + 
                    result.numOfCoordPerTexCoord + 
                    result.numOfCoordPerNormal +
                    result.numOfCoordPerBinormal + 
                    result.numOfCoordPerTangent) * sizeof(GLfloat)
