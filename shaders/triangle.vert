#version 450

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_color;
layout(location = 2) in vec2 in_tex_coord;

layout(location = 0) out vec3 out_color;
layout(location = 1) out vec2 out_tex_coord;

layout(push_constant) uniform PushConsts
{
	mat4 matrix;
} push_consts;

void main() {
    gl_Position = push_consts.matrix * vec4(in_pos, 1.0);
    out_color = in_color;
	out_tex_coord = in_tex_coord;
}
