import nimx/[portable_gl, matrixes, types, context, formatted_text, font]
import rod/material/shader
import math
import opengl

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
uniform vec4 uColor;
void main() { gl_FragColor = uColor; }
"""

const greenColor = newColor(0.2, 1.0, 0.2, 1.0)
var debugDrawShader = newShader(vertexShader, fragmentShader,
            @[(0.GLuint, "aPosition")])

let boxIndexData = [0.GLushort, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 3, 7, 2, 6, 0, 4, 1, 5]
var boxIB: BufferRef

proc DDdrawBox*(minPoint, maxPoint: Vector3, color: Color = greenColor) =
    let c = currentContext()
    let gl = c.gl

    var i: uint = 0
    template v(f: GLfloat) =
        c.vertexes[i] = f
        inc i

    v minPoint.x; v minPoint.y; v minPoint.z
    v maxPoint.x; v minPoint.y; v minPoint.z
    v maxPoint.x; v maxPoint.y; v minPoint.z
    v minPoint.x; v maxPoint.y; v minPoint.z

    v minPoint.x; v minPoint.y; v maxPoint.z
    v maxPoint.x; v minPoint.y; v maxPoint.z
    v maxPoint.x; v maxPoint.y; v maxPoint.z
    v minPoint.x; v maxPoint.y; v maxPoint.z

    if boxIB == invalidBuffer:
        boxIB = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, boxIB)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, boxIndexData, gl.STATIC_DRAW)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, boxIB)
    gl.enableVertexAttribArray(0);
    c.bindVertexData(24)
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0)

    debugDrawShader.bindShader()
    debugDrawShader.setTransformUniform()
    debugDrawShader.setUniform("uColor", color)
    gl.drawElements(gl.LINES, boxIndexData.len.GLsizei, gl.UNSIGNED_SHORT)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)

proc DDdrawBox*(size: Vector3) =
    let minPoint = -size / 2.0
    let maxPoint = size / 2.0
    DDdrawBox(minPoint, maxPoint)

proc DDdrawCircle*(pos: Vector3, radius: float32, color: Color = greenColor) =
    const pointsCount = 36
    let c = currentContext()

    for i in 0 ..< pointsCount:
        let angle = degToRad(i * 360 / pointsCount)
        c.vertexes[3*i + 0] = cos(angle) * radius + pos.x
        c.vertexes[3*i + 1] = 0.0 + pos.y
        c.vertexes[3*i + 2] = sin(angle) * radius + pos.z

    let gl = c.gl
    gl.enableVertexAttribArray(0)
    c.bindVertexData(pointsCount * 3)
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0)

    debugDrawShader.bindShader()
    debugDrawShader.setUniform("uColor", color)
    debugDrawShader.setTransformUniform()
    gl.drawArrays(gl.LINE_LOOP, 0, pointsCount)

proc DDdrawCircleX*(pos: Vector3, radius: float32, color: Color = greenColor) =
    const pointsCount = 36
    let c = currentContext()

    for i in 0 ..< pointsCount:
        let angle = degToRad(i * 360 / pointsCount)
        c.vertexes[3*i + 0] = pos.x
        c.vertexes[3*i + 1] = cos(angle) * radius + + pos.y
        c.vertexes[3*i + 2] = sin(angle) * radius + pos.z

    let gl = c.gl
    gl.enableVertexAttribArray(0)
    c.bindVertexData(pointsCount * 3)
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0)

    debugDrawShader.bindShader()
    debugDrawShader.setUniform("uColor", color)
    debugDrawShader.setTransformUniform()
    gl.drawArrays(gl.LINE_LOOP, 0, pointsCount)

proc DDdrawCircleZ*(pos: Vector3, radius: float32, color: Color = greenColor) =
    const pointsCount = 36
    let c = currentContext()

    for i in 0 ..< pointsCount:
        let angle = degToRad(i * 360 / pointsCount)
        c.vertexes[3*i + 0] = cos(angle) * radius + pos.x
        c.vertexes[3*i + 1] = sin(angle) * radius + pos.y
        c.vertexes[3*i + 2] = pos.z

    let gl = c.gl
    gl.enableVertexAttribArray(0);
    c.bindVertexData(pointsCount * 3)
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0)

    debugDrawShader.bindShader()
    debugDrawShader.setUniform("uColor", color)
    debugDrawShader.setTransformUniform()
    gl.drawArrays(gl.LINE_LOOP, 0, pointsCount)

proc DDdrawLine*(p1, p2: Vector3, color: Color = greenColor) =
    let c = currentContext()
    c.vertexes[0] = p1.x
    c.vertexes[1] = p1.y
    c.vertexes[2] = p1.z
    c.vertexes[3] = p2.x
    c.vertexes[4] = p2.y
    c.vertexes[5] = p2.z

    let gl = c.gl
    gl.enableVertexAttribArray(0)
    c.bindVertexData(2 * 3)
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0)

    debugDrawShader.bindShader()
    debugDrawShader.setUniform("uColor", color)
    debugDrawShader.setTransformUniform()
    gl.drawArrays(gl.LINES, 0, 2)

proc DDdrawArrow*(dist: float32, color: Color = greenColor) =
    DDdrawLine( newVector3(0.0), newVector3(0.0, dist, 0.0), color )

    DDdrawLine( newVector3(0.0, dist, 0.0), newVector3(dist / 8.0, dist * 3.0 / 4.0, dist / 8.0), color )
    DDdrawLine( newVector3(0.0, dist, 0.0), newVector3(-dist / 8.0, dist * 3.0 / 4.0, dist / 8.0), color )
    DDdrawLine( newVector3(0.0, dist, 0.0), newVector3(-dist / 8.0, dist * 3.0 / 4.0, -dist / 8.0), color )
    DDdrawLine( newVector3(0.0, dist, 0.0), newVector3(dist / 8.0, dist * 3.0 / 4.0, -dist / 8.0), color )

proc DDdrawRect*(rect: Rect, color: Color = greenColor) =
    DDdrawLine( newVector3(rect.x, rect.y, 0.0), newVector3(rect.x + rect.width, rect.y, 0.0), color )
    DDdrawLine( newVector3(rect.x, rect.y, 0.0), newVector3(rect.x, rect.y + rect.height, 0.0), color )
    DDdrawLine( newVector3(rect.x + rect.width, rect.y, 0.0), newVector3(rect.x + rect.width, rect.y + rect.height, 0.0), color )
    DDdrawLine( newVector3(rect.x, rect.y + rect.height, 0.0), newVector3(rect.x + rect.width, rect.y + rect.height, 0.0), color )

proc DDdrawText*(text: string, p: Point, size: float = 16.0, color: Color = greenColor) =
    var fText = newFormattedText()
    let font = systemFontOfSize(size)
    fText.setFontInRange(0, -1, font)
    fText.text = text
    fText.setTextColorInRange(0, -1, color)

    currentContext().drawText(p, fText)

const GridVertexShader = """
attribute vec3 aPosition;

uniform mat4 modelViewProjectionMatrix;

void main()
{
    gl_Position = modelViewProjectionMatrix * vec4(aPosition, 1.0);
}
"""
const GridFragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform vec4 uColor;

void main()
{
    gl_FragColor = uColor;
}
"""

var gridShader: Shader

proc DDdrawGrid*(r: Rect, s: Size) =
    let c = currentContext()
    let gl = c.gl

    let xLines = ceil(r.width / s.width).int
    let yLines = ceil(r.height / s.height).int
    
    let totalVetexes = (xLines + yLines) * 6
    let drawCalls = ceil(totalVetexes/c.vertexes.len).int
   
    if gridShader.isNil:
        gridShader = newShader(GridVertexShader, GridFragmentShader, @[(0.GLuint, "aPosition")])

    gridShader.bindShader()
    gridShader.setTransformUniform()

    gridShader.setUniform("uColor", c.strokeColor)

    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0)
    
    # gl.depthMask(true)
    # gl.enable(gl.DEPTH_TEST)

    template lineYIndex(i: int): int = i * 6
    template lineXIndex(i: int): int = 6 * i + (yToDraw) * 6

    var draw = 0
    var curX, curY: int
    while draw < drawCalls:
        var yToDraw = 0
        var xToDraw = 0

        for i in curY ..< yLines:
            var p1 = newVector3(0.0, i.float * s.height) + newVector3(r.x, r.y)
            var p2 = newVector3(r.width, i.float * s.height) + newVector3(r.x, r.y)
            
            let index = lineYIndex(yToDraw)
            c.vertexes[index + 0] = p1.x
            c.vertexes[index + 1] = p1.y
            c.vertexes[index + 2] = p1.z
            c.vertexes[index + 3] = p2.x
            c.vertexes[index + 4] = p2.y
            c.vertexes[index + 5] = p2.z
            inc yToDraw

            if lineYIndex(yToDraw) + 5 >= c.vertexes.len:
                break 
        curY += yToDraw

        if lineXIndex(0) + 5 < c.vertexes.len:
            for i in curX ..< xLines:
                var p1 = newVector3(i.float * s.width, 0.0) + newVector3(r.x, r.y)
                var p2 = newVector3(i.float * s.width, r.height) + newVector3(r.x, r.y)
                
                let index = lineXIndex(xToDraw)
                c.vertexes[index + 0] = p1.x
                c.vertexes[index + 1] = p1.y
                c.vertexes[index + 2] = p1.z
                c.vertexes[index + 3] = p2.x
                c.vertexes[index + 4] = p2.y
                c.vertexes[index + 5] = p2.z
                inc xToDraw

                if lineXIndex(xToDraw) + 5 >= c.vertexes.len:
                    break 
        curX += xToDraw

        let vertexesToDraw = yToDraw + xToDraw
        c.bindVertexData(6 * vertexesToDraw)
        gl.drawArrays(gl.LINES, 0, GLsizei(vertexesToDraw * 4))
        inc draw

    # gl.disable(gl.DEPTH_TEST)
    # gl.depthMask(true)
    gl.disableVertexAttribArray(0)
