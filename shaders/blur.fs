#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

// blur direction: (1.0, 0.0) for horizontal, (0.0, 1.0) for vertical
uniform vec2 direction;
uniform vec2 resolution;

out vec4 finalColor;

void main()
{
    vec2 texelSize = 1.0 / resolution;
    vec4 sum = vec4(0.0);

    // 9-tap gaussian blur
    float weights[9] = float[](
        0.0162, 0.0540, 0.1216, 0.1945, 0.2270,
        0.1945, 0.1216, 0.0540, 0.0162
    );

    for (int i = -4; i <= 4; i++) {
        vec2 offset = direction * float(i) * texelSize * 2.0;
        sum += texture(texture0, fragTexCoord + offset) * weights[i + 4];
    }

    finalColor = sum * colDiffuse * fragColor;
}
