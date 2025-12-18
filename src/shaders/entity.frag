#version 430

in vec2 fragTexCoord;
in vec3 fragColor;

uniform sampler2D circleTexture;
uniform bool opaqueMode;

out vec4 finalColor;

void main() {
    float alpha = texture(circleTexture, fragTexCoord).r;

    if (opaqueMode) {
        // alpha-test: discard transparent pixels, render rest as opaque
        // allows early-Z rejection of occluded fragments
        if (alpha < 0.5) discard;
        finalColor = vec4(fragColor, 1.0);
    } else {
        finalColor = vec4(fragColor, alpha);
    }
}
