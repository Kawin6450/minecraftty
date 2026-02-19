const std = @import("std");
const vk = @import("vulkan");
const vku = @import("vkutils.zig");
const za = @import("zalgebra");
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;

pub const Vertex = struct {
    pub const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    pub const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "tex_coord"),
        },
    };

    pos: [3]f32,
    color: [3]f32,
    tex_coord: [2]f32,
};

pub const Geometry = struct {
    vertices: []const Vertex = &.{},
    indices: []const u16 = &.{},

    _buffer: ?vku.Buffer = null,
    _index_buffer: ?vku.Buffer = null,

    pub fn fromVerticesAndIndices(gc: *const GraphicsContext, pool: vk.CommandPool, vertices: []const Vertex, indices: []const u16) !Geometry {
        var geometry = Geometry{
            .vertices = vertices,
            .indices = indices,
        };
        try uploadVerticesAndIndices(&geometry, gc, pool);
        return geometry;
    }

    pub fn destroy(geometry: *Geometry, gc: *const GraphicsContext) void {
        if (geometry._buffer) |buffer| {
            vku.destroyBuffer(gc, buffer);
            geometry._buffer = null;
        }
        if (geometry._index_buffer) |buffer| {
            vku.destroyBuffer(gc, buffer);
            geometry._index_buffer = null;
        }
    }

    pub fn destroyWithVerticesAndIndices(geometry: *Geometry, alloc: std.mem.Allocator, gc: *const GraphicsContext) void {
        alloc.free(geometry.vertices);
        alloc.free(geometry.indices);
        destroy(geometry, gc);
    }

    fn uploadVerticesAndIndices(geometry: *Geometry, gc: *const GraphicsContext, pool: vk.CommandPool) !void {
        // Dispose the old buffers
        if (geometry._buffer) |buffer| {
            vku.destroyBuffer(gc, buffer);
        }
        if (geometry._index_buffer) |buffer| {
            vku.destroyBuffer(gc, buffer);
        }

        // Create vertex buffer
        const buffer_size = geometry.vertices.len * @sizeOf(Vertex);
        const buffer = try vku.createBuffer(gc, buffer_size, .{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, .{ .device_local_bit = true });
        geometry._buffer = buffer;

        // Create staging buffer
        const staging_buffer = try vku.createBuffer(gc, buffer_size, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
        defer vku.destroyBuffer(gc, staging_buffer);

        // Upload to staging buffer
        {
            const data = try gc.dev.mapMemory(staging_buffer.mem, 0, vk.WHOLE_SIZE, .{});
            defer gc.dev.unmapMemory(staging_buffer.mem);

            const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(data));
            @memcpy(gpu_vertices, geometry.vertices);
        }

        // Copy staging buffer to actual buffer
        try vku.copyBuffer(gc, pool, staging_buffer.buffer, buffer.buffer, buffer_size);

        // Create index buffer
        const index_buffer_size = geometry.indices.len * @sizeOf(u16);
        const index_buffer = try vku.createBuffer(gc, index_buffer_size, .{ .index_buffer_bit = true, .transfer_dst_bit = true }, .{ .device_local_bit = true });
        geometry._index_buffer = index_buffer;

        // Create staging buffer
        const index_staging_buffer = try vku.createBuffer(gc, index_buffer_size, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
        defer vku.destroyBuffer(gc, index_staging_buffer);

        // Upload to staging buffer
        {
            const data = try gc.dev.mapMemory(index_staging_buffer.mem, 0, vk.WHOLE_SIZE, .{});
            defer gc.dev.unmapMemory(index_staging_buffer.mem);

            const gpu_indices: [*]u16 = @ptrCast(@alignCast(data));
            @memcpy(gpu_indices, geometry.indices);
        }

        // Copy staging buffer to actual buffer
        try vku.copyBuffer(gc, pool, index_staging_buffer.buffer, index_buffer.buffer, index_buffer_size);
    }
};
