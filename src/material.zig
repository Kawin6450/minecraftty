const std = @import("std");
const vk = @import("vulkan");
const vku = @import("vkutils.zig");
const za = @import("zalgebra");
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Vertex = @import("geometry.zig").Vertex;
const Node = @import("node.zig").Node;
const Camera = @import("camera.zig").Camera;
const zigimg = @import("zigimg");

const vert_spv align(@alignOf(u32)) = @embedFile("vertex_shader").*;
const frag_spv align(@alignOf(u32)) = @embedFile("fragment_shader").*;

const PushConstants = struct {
    const range = vk.PushConstantRange{
        .offset = 0,
        .size = @sizeOf(PushConstants),
        .stage_flags = .{ .vertex_bit = true },
    };

    matrix: za.Mat4,
};

const Uniforms = struct {
    color: [4]f32,
};

//pub fn Material(comptime T: type) type {
//}
pub const Material = struct {
    alloc: std.mem.Allocator,

    uniforms: Uniforms = .{ .color = .{ 1, 0, 0, 1 } },

    _descriptor_set_layout: vk.DescriptorSetLayout,
    _descriptor_pool: vk.DescriptorPool,
    _descriptor_sets: [1]vk.DescriptorSet,

    _uniforms_buffer: vku.Buffer,
    _sampler: vk.Sampler,
    _tex_image: zigimg.Image,
    _tex_vk_image: vku.Image,

    _vert: vk.ShaderModule,
    _frag: vk.ShaderModule,

    _layout: vk.PipelineLayout,
    _pipeline: vk.Pipeline,

    pub fn new(
        alloc: std.mem.Allocator,
        gc: *const GraphicsContext,
        cmdpool: vk.CommandPool,
        render_pass: vk.RenderPass,
    ) !Material {
        var material: Material = undefined;

        material.alloc = alloc;

        // Descriptor sets

        var descriptor_set_bindings = [_]vk.DescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptor_type = .uniform_buffer,
                .descriptor_count = 1,
                .stage_flags = .{ .fragment_bit = true },
            },
            .{
                .binding = 1,
                .descriptor_type = .combined_image_sampler,
                .descriptor_count = 1,
                .stage_flags = .{ .fragment_bit = true },
            },
        };
        const descriptor_set_layout = try gc.dev.createDescriptorSetLayout(&.{
            .binding_count = descriptor_set_bindings.len,
            .p_bindings = @ptrCast(&descriptor_set_bindings),
        }, null);

        var descriptor_pool_sizes = [_]vk.DescriptorPoolSize{
            .{ .type = .uniform_buffer, .descriptor_count = 1 },
            .{ .type = .combined_image_sampler, .descriptor_count = 1 },
        };
        const descriptor_pool = try gc.dev.createDescriptorPool(&.{
            .pool_size_count = descriptor_pool_sizes.len,
            .p_pool_sizes = @ptrCast(&descriptor_pool_sizes),
            .max_sets = 2,
        }, null);

        var descriptor_sets: [1]vk.DescriptorSet = undefined;
        try gc.dev.allocateDescriptorSets(&.{
            .descriptor_pool = descriptor_pool,
            .descriptor_set_count = 1,
            .p_set_layouts = @ptrCast(&descriptor_set_layout),
        }, @ptrCast(&descriptor_sets));

        material._descriptor_set_layout = descriptor_set_layout;
        material._descriptor_pool = descriptor_pool;
        material._descriptor_sets = descriptor_sets;

        // Write to uniforms

        const uniforms_buffer = try vku.createBuffer(gc, @sizeOf(Uniforms), .{ .uniform_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
        material._uniforms_buffer = uniforms_buffer;

        {
            const data = try material._uniforms_buffer.map(gc);
            defer gc.dev.unmapMemory(material._uniforms_buffer.mem);

            const gpu_uniforms: *Uniforms = @ptrCast(@alignCast(data));
            gpu_uniforms.* = material.uniforms;
        }

        const write_uniforms_buffer_info = vk.DescriptorBufferInfo{
            .buffer = uniforms_buffer.buffer,
            .offset = 0,
            .range = uniforms_buffer.size,
        };
        const write_uniforms = vk.WriteDescriptorSet{
            .dst_set = material._descriptor_sets[0],
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .p_buffer_info = @ptrCast(&write_uniforms_buffer_info),
            .p_image_info = &[0]vk.DescriptorImageInfo{},
            .p_texel_buffer_view = &[0]vk.BufferView{},
        };
        gc.dev.updateDescriptorSets(1, @ptrCast(&write_uniforms), 0, null);

        // Write to texture

        var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var tex_image = try zigimg.Image.fromFilePath(alloc, "textures/blocks.png", &read_buffer);
        try tex_image.convert(alloc, zigimg.PixelFormat.rgba32);
        const tex_vk_image = try vku.createImage(gc, .r8g8b8a8_unorm, @intCast(tex_image.width), @intCast(tex_image.height), .optimal, .{ .sampled_bit = true, .transfer_dst_bit = true }, .{ .device_local_bit = true }, .{ .color_bit = true });
        material._tex_image = tex_image;
        material._tex_vk_image = tex_vk_image;

        {
            const byte_size = tex_image.imageByteSize();

            const staging_buf = try vku.createBuffer(gc, byte_size, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
            defer vku.destroyBuffer(gc, staging_buf);

            {
                const data = try gc.dev.mapMemory(staging_buf.mem, 0, byte_size, .{});
                defer gc.dev.unmapMemory(staging_buf.mem);

                const pixels_gpu: [*]zigimg.color.Rgba32 = @ptrCast(@alignCast(data));
                @memcpy(pixels_gpu, tex_image.pixels.rgba32);
            }

            try vku.transitionImageLayout(gc, cmdpool, .undefined, .transfer_dst_optimal, tex_vk_image.image, .r8g8b8a8_unorm);
            try vku.copyBufferToImage(gc, cmdpool, staging_buf.buffer, tex_vk_image.image, @intCast(tex_image.width), @intCast(tex_image.height));
            try vku.transitionImageLayout(gc, cmdpool, .transfer_dst_optimal, .shader_read_only_optimal, tex_vk_image.image, .r8g8b8a8_unorm);
        }

        const sampler = try gc.dev.createSampler(&.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .anisotropy_enable = .false,
            .max_anisotropy = gc.props.limits.max_sampler_anisotropy,
            .border_color = .int_opaque_black,
            .unnormalized_coordinates = .false,
            .compare_enable = .false,
            .compare_op = .always,
            .mipmap_mode = .nearest,
            .mip_lod_bias = 0,
            .min_lod = 0,
            .max_lod = 0,
        }, null);
        material._sampler = sampler;

        const write_texture_image_info = vk.DescriptorImageInfo{
            .image_layout = .shader_read_only_optimal,
            .image_view = tex_vk_image.view,
            .sampler = sampler,
        };
        const write_texture = vk.WriteDescriptorSet{
            .dst_set = material._descriptor_sets[0],
            .dst_binding = 1,
            .dst_array_element = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .p_buffer_info = &[0]vk.DescriptorBufferInfo{},
            .p_image_info = @ptrCast(&write_texture_image_info),
            .p_texel_buffer_view = &[0]vk.BufferView{},
        };
        gc.dev.updateDescriptorSets(1, @ptrCast(&write_texture), 0, null);

        // Shaders

        const vert = try gc.dev.createShaderModule(&.{
            .code_size = vert_spv.len,
            .p_code = @ptrCast(&vert_spv),
        }, null);
        material._vert = vert;

        const frag = try gc.dev.createShaderModule(&.{
            .code_size = frag_spv.len,
            .p_code = @ptrCast(&frag_spv),
        }, null);
        material._frag = frag;

        // Pipeline

        const layout = try gc.dev.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast(&descriptor_set_layout),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast(&PushConstants.range),
        }, null);
        material._layout = layout;

        try material.createPipeline(gc, vert, frag, layout, render_pass);

        return material;
    }

    pub fn destroy(material: *Material, gc: *const GraphicsContext) void {
        gc.dev.destroyPipeline(material._pipeline, null);
        vku.destroyImage(gc, material._tex_vk_image);
        material._tex_image.deinit(material.alloc);
        gc.dev.destroySampler(material._sampler, null);
        vku.destroyBuffer(gc, material._uniforms_buffer);
        gc.dev.destroyDescriptorPool(material._descriptor_pool, null); // Also frees descriptor sets
        gc.dev.destroyDescriptorSetLayout(material._descriptor_set_layout, null);
        gc.dev.destroyPipelineLayout(material._layout, null);
        gc.dev.destroyShaderModule(material._vert, null);
        gc.dev.destroyShaderModule(material._frag, null);
    }

    fn createPipeline(
        material: *Material,
        gc: *const GraphicsContext,
        vert: vk.ShaderModule,
        frag: vk.ShaderModule,
        layout: vk.PipelineLayout,
        render_pass: vk.RenderPass,
    ) !void {
        const pssci = [_]vk.PipelineShaderStageCreateInfo{
            .{
                .stage = .{ .vertex_bit = true },
                .module = vert,
                .p_name = "main",
            },
            .{
                .stage = .{ .fragment_bit = true },
                .module = frag,
                .p_name = "main",
            },
        };

        const pvisci = vk.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
            .vertex_attribute_description_count = Vertex.attribute_description.len,
            .p_vertex_attribute_descriptions = &Vertex.attribute_description,
        };

        const piasci = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        };

        const pvsci = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .p_viewports = undefined, // set in createCommandBuffers with cmdSetViewport
            .scissor_count = 1,
            .p_scissors = undefined, // set in createCommandBuffers with cmdSetScissor
        };

        const prsci = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        };

        const pmsci = vk.PipelineMultisampleStateCreateInfo{
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = .false,
            .min_sample_shading = 1,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };

        const pcbas = vk.PipelineColorBlendAttachmentState{
            .blend_enable = .false,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        };

        const pdssci = vk.PipelineDepthStencilStateCreateInfo{
            .depth_test_enable = .true,
            .depth_write_enable = .true,
            .depth_compare_op = .less,
            .depth_bounds_test_enable = .false,
            .min_depth_bounds = 0,
            .max_depth_bounds = 1,
            .stencil_test_enable = .false,
            .front = std.mem.zeroes(vk.StencilOpState),
            .back = std.mem.zeroes(vk.StencilOpState),
        };

        const pcbsci = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&pcbas),
            .blend_constants = [_]f32{ 0, 0, 0, 0 },
        };

        const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
        const pdsci = vk.PipelineDynamicStateCreateInfo{
            .flags = .{},
            .dynamic_state_count = dynstate.len,
            .p_dynamic_states = &dynstate,
        };

        const gpci = vk.GraphicsPipelineCreateInfo{
            .flags = .{},
            .stage_count = 2,
            .p_stages = &pssci,
            .p_vertex_input_state = &pvisci,
            .p_input_assembly_state = &piasci,
            .p_tessellation_state = null,
            .p_viewport_state = &pvsci,
            .p_rasterization_state = &prsci,
            .p_multisample_state = &pmsci,
            .p_depth_stencil_state = &pdssci,
            .p_color_blend_state = &pcbsci,
            .p_dynamic_state = &pdsci,
            .layout = layout,
            .render_pass = render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        var pipeline: vk.Pipeline = undefined;
        _ = try gc.dev.createGraphicsPipelines(
            .null_handle,
            1,
            @ptrCast(&gpci),
            null,
            @ptrCast(&pipeline),
        );
        material._pipeline = pipeline;
    }

    pub fn recordCommandBuffer(
        material: *Material,
        gc: *const GraphicsContext,
        cmdbuf: vk.CommandBuffer,
        node: *const Node,
        camera: *Camera,
    ) !void {
        gc.dev.cmdBindPipeline(cmdbuf, .graphics, material._pipeline);

        gc.dev.cmdBindDescriptorSets(cmdbuf, .graphics, material._layout, 0, material._descriptor_sets.len, &material._descriptor_sets, 0, null);

        const push_consts = PushConstants{
            .matrix = camera.getProjViewMatrix().mul(node.transform),
        };
        gc.dev.cmdPushConstants(cmdbuf, material._layout, .{ .vertex_bit = true }, 0, @sizeOf(PushConstants), &push_consts);

        const offset = [_]vk.DeviceSize{0};
        gc.dev.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&node.geometry._buffer.?.buffer), &offset);
        gc.dev.cmdBindIndexBuffer(cmdbuf, node.geometry._index_buffer.?.buffer, 0, .uint16);
        gc.dev.cmdDrawIndexed(cmdbuf, @intCast(node.geometry.indices.len), 1, 0, 0, 0);
    }
};
