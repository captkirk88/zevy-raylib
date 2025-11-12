#version 100

// Simple fragment shader compatible with raylib

precision mediump float;

varying vec2 fragTexCoord;
varying vec4 fragColor;

uniform sampler2D texture0;       // Texture sampler
uniform vec4 colDiffuse;          // Tint color

void main() {
    // Sample texture
    vec4 texelColor = texture2D(texture0, fragTexCoord);

    // Apply color tinting
    gl_FragColor = texelColor * colDiffuse * fragColor;
}
