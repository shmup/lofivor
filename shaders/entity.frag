#version 430

in vec2 fragTexCoord;
in vec3 fragColor;

uniform sampler2D circleTexture;

out vec4 finalColor;

void main() {
    float alpha = texture(circleTexture, fragTexCoord).r;
    finalColor = vec4(fragColor, alpha);
}
