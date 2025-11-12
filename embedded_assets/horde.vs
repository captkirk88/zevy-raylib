#version 100

// Simple vertex shader compatible with raylib
// Uses standard raylib attribute names and locations

attribute vec3 vertexPosition;    // Vertex position (raylib uses vec3)
attribute vec2 vertexTexCoord;    // Texture coordinates
attribute vec4 vertexColor;       // Vertex color

varying vec2 fragTexCoord;
varying vec4 fragColor;

uniform mat4 mvp;                  // Model-View-Projection matrix

void main() {
    // Transform vertex position
    gl_Position = mvp * vec4(vertexPosition, 1.0);

    // Pass texture coordinates and color to fragment shader
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
}
