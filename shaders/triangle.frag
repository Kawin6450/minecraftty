#version 450

layout(location = 0) in vec3 v_color;
layout(location = 1) in vec2 tex_coord;

layout(binding = 0) uniform Uniforms {
	vec4 u_color;
};

layout(binding = 1) uniform sampler2D u_texture;

layout(location = 0) out vec4 color;

void main() {
	//color = vec4(1.0, 1.0, 1.0, 1.0);
    //color = vec4(v_color, 1.0);
    //color = u_color;
	//color = vec4(tex_coord, 0.0, 1.0);
	color = texture(u_texture, tex_coord);
}
