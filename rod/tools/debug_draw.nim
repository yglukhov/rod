import math
import opengl

import nimx.portable_gl
import nimx.matrixes
import nimx.types
import nimx.context

import rod.material.shader

const vertexShader = """
attribute vec4 aPosition;
uniform mat4 modelViewProjectionMatrix;
void main() { gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0); }
"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
void main() { gl_FragColor = vec4(0.2, 1.2, 0.2, 1.0); }
"""

var debugDrawShader = newShader(vertexShader, fragmentShader,
            @[(0.GLuint, "aPosition")])

let boxIndexData = [0.GLushort, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 3, 7, 2, 6, 0, 4, 1, 5]
var boxIB: BufferRef

var boxPoints: seq[GLfloat]
proc DDdrawBox*(minPoint, maxPoint: Vector3) =
    boxPoints = newSeq[GLfloat]()
    boxPoints.add([minPoint.x, minPoint.y, minPoint.z])
    boxPoints.add([maxPoint.x, minPoint.y, minPoint.z])
    boxPoints.add([maxPoint.x, maxPoint.y, minPoint.z])
    boxPoints.add([minPoint.x, maxPoint.y, minPoint.z])

    boxPoints.add([minPoint.x, minPoint.y, maxPoint.z])
    boxPoints.add([maxPoint.x, minPoint.y, maxPoint.z])
    boxPoints.add([maxPoint.x, maxPoint.y, maxPoint.z])
    boxPoints.add([minPoint.x, maxPoint.y, maxPoint.z])

    let gl = currentContext().gl
    if boxIB == invalidBuffer:
        boxIB = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, boxIB)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, boxIndexData, gl.STATIC_DRAW)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, boxIB)
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, false, 0, boxPoints)

    debugDrawShader.bindShader()
    debugDrawShader.setTransformUniform()
    gl.drawElements(gl.LINES, boxIndexData.len.GLsizei, gl.UNSIGNED_SHORT)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)

proc DDdrawBox*(size: Vector3) =
    let minPoint = -size / 2.0
    let maxPoint = size / 2.0
    DDdrawBox(minPoint, maxPoint)

proc DDdrawCircle*(pos: Vector3, radius: float32) =
    const pointsCount = 36
    var points : array[pointsCount * 3, float32]

    for i in 0..pointsCount - 1:
        let angle = degToRad(i * 360 / pointsCount)
        points[3*i + 0] = cos(angle) * radius + pos.x
        points[3*i + 1] = 0.0 + pos.y
        points[3*i + 2] = sin(angle) * radius + pos.z

    let gl = currentContext().gl
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, false, 0, points)

    debugDrawShader.bindShader()
    debugDrawShader.setTransformUniform()
    gl.drawArrays(gl.LINE_LOOP, 0, pointsCount)

proc DDdrawCircleX*(pos: Vector3, radius: float32) =
    const pointsCount = 36
    var points : array[pointsCount * 3, float32]

    for i in 0..pointsCount - 1:
        let angle = degToRad(i * 360 / pointsCount)
        points[3*i + 0] = pos.x
        points[3*i + 1] = cos(angle) * radius + + pos.y
        points[3*i + 2] = sin(angle) * radius + pos.z

    let gl = currentContext().gl
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, false, 0, points)

    debugDrawShader.bindShader()
    debugDrawShader.setTransformUniform()
    gl.drawArrays(gl.LINE_LOOP, 0, pointsCount)

proc DDdrawCircleZ*(pos: Vector3, radius: float32) =
    const pointsCount = 36
    var points : array[pointsCount * 3, float32]

    for i in 0..pointsCount - 1:
        let angle = degToRad(i * 360 / pointsCount)
        points[3*i + 0] = cos(angle) * radius + pos.x
        points[3*i + 1] = sin(angle) * radius + pos.y
        points[3*i + 2] = pos.z

    let gl = currentContext().gl
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, false, 0, points)

    debugDrawShader.bindShader()
    debugDrawShader.setTransformUniform()
    gl.drawArrays(gl.LINE_LOOP, 0, pointsCount)

proc DDdrawLine*(p1, p2: Vector3) =
    var points : array[2 * 3, float32]
    points[0] = p1.x
    points[1] = p1.y
    points[2] = p1.z
    points[3] = p2.x
    points[4] = p2.y
    points[5] = p2.z

    let gl = currentContext().gl
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, false, 0, points)

    debugDrawShader.bindShader()
    debugDrawShader.setTransformUniform()
    gl.drawArrays(gl.LINES, 0, 2)

proc DDdrawArrow*(dist: float32) =
    DDdrawLine( newVector3(0.0), newVector3(0.0, dist, 0.0) )

    DDdrawLine( newVector3(0.0, dist, 0.0), newVector3(dist / 8.0, dist * 3.0 / 4.0, dist / 8.0) )
    DDdrawLine( newVector3(0.0, dist, 0.0), newVector3(-dist / 8.0, dist * 3.0 / 4.0, dist / 8.0) )
    DDdrawLine( newVector3(0.0, dist, 0.0), newVector3(-dist / 8.0, dist * 3.0 / 4.0, -dist / 8.0) )
    DDdrawLine( newVector3(0.0, dist, 0.0), newVector3(dist / 8.0, dist * 3.0 / 4.0, -dist / 8.0) )
