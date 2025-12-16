#version 430

// quad corner position (-0.5 to 0.5)
layout(location = 0) in vec2 position;
layout(location = 1) in vec2 texCoord;

// entity data from SSBO
struct Entity {
    float x;
    float y;
    uint color;
};

layout(std430, binding = 0) readonly buffer EntityData {
    Entity entities[];
};

// screen size for NDC conversion
uniform vec2 screenSize;

out vec2 fragTexCoord;
out vec3 fragColor;

void main() {
    // get entity data from SSBO
    Entity e = entities[gl_InstanceID];

    // convert entity position to NDC
    // entity coords are in screen pixels, convert to [-1, 1]
    float ndcX = (e.x / screenSize.x) * 2.0 - 1.0;
    float ndcY = (e.y / screenSize.y) * 2.0 - 1.0;

    // quad size in NDC (16 pixels)
    float quadSizeNdc = 16.0 / screenSize.x;

    // offset by quad corner position
    gl_Position = vec4(ndcX + position.x * quadSizeNdc,
                       ndcY + position.y * quadSizeNdc,
                       0.0, 1.0);

    // extract RGB from packed color (0xRRGGBB)
    float r = float((e.color >> 16u) & 0xFFu) / 255.0;
    float g = float((e.color >> 8u) & 0xFFu) / 255.0;
    float b = float(e.color & 0xFFu) / 255.0;
    fragColor = vec3(r, g, b);

    fragTexCoord = texCoord;
}
