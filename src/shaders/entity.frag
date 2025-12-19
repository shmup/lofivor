#version 430

in vec2 fragTexCoord;
in vec3 fragColor;

uniform sampler2D circleTexture;
uniform bool opaqueMode;

out vec4 finalColor;

void main() {
    if (opaqueMode) {
        // solid squares - no texture, no discard = true early-Z
        finalColor = vec4(fragColor, 1.0);
    } else {
        float alpha = texture(circleTexture, fragTexCoord).r;
        finalColor = vec4(fragColor, alpha);
    }
}
