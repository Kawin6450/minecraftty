const std = @import("std");
const vk = @import("vulkan");
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;

fn findMemoryTypeIndex(gc: *const GraphicsContext, type_bits: u32, properties: vk.MemoryPropertyFlags) !u32 {
    var i: u5 = 0;
    while (i < gc.mem_props.memory_type_count) : (i += 1) {
        if (type_bits & (@as(u32, 1) << i) != 0 and
            @as(u32, @bitCast(gc.mem_props.memory_types[i].property_flags)) & @as(u32, @bitCast(properties)) != 0)
        {
            return i;
        }
    }
    return error.FailFindMemoryType;
}

pub fn beginOneTimeCommandBuffer(gc: *const GraphicsContext, cmdpool: vk.CommandPool) !vk.CommandBuffer {
    var cmdbuf: vk.CommandBuffer = undefined;
    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = cmdpool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf));

    try gc.dev.beginCommandBuffer(cmdbuf, &.{
        .flags = .{ .one_time_submit_bit = true },
    });

    return cmdbuf;
}

pub fn endOneTimeCommandBuffer(gc: *const GraphicsContext, cmdpool: vk.CommandPool, cmdbuf: vk.CommandBuffer) !void {
    try gc.dev.endCommandBuffer(cmdbuf);

    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmdbuf),
    };
    try gc.dev.queueSubmit(gc.graphics_queue.handle, 1, @ptrCast(&submit_info), .null_handle);
    try gc.dev.queueWaitIdle(gc.graphics_queue.handle);

    gc.dev.freeCommandBuffers(cmdpool, 1, @ptrCast(&cmdbuf));
}

pub const Image = struct {
    image: vk.Image,
    mem: vk.DeviceMemory,
    view: vk.ImageView,
};

pub fn createImage(gc: *const GraphicsContext, format: vk.Format, width: u32, height: u32, tiling: vk.ImageTiling, usage: vk.ImageUsageFlags, memory_props: vk.MemoryPropertyFlags, aspect_mask: vk.ImageAspectFlags) !Image {
    var image: Image = undefined;

    // Image
    image.image = try gc.dev.createImage(&.{
        .image_type = .@"2d",
        .format = format,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = tiling,
        .usage = usage,
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null);

    // Memory
    const mem_requirements = gc.dev.getImageMemoryRequirements(image.image);
    const mem_type_index = try findMemoryTypeIndex(gc, mem_requirements.memory_type_bits, memory_props);
    image.mem = try gc.dev.allocateMemory(&.{
        .allocation_size = mem_requirements.size,
        .memory_type_index = mem_type_index,
    }, null);
    try gc.dev.bindImageMemory(image.image, image.mem, 0);

    // View
    image.view = try gc.dev.createImageView(&.{
        .image = image.image,
        .view_type = .@"2d",
        .format = format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = aspect_mask,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);

    return image;
}

pub fn destroyImage(gc: *const GraphicsContext, image: Image) void {
    gc.dev.destroyImage(image.image, null);
    gc.dev.freeMemory(image.mem, null);
    gc.dev.destroyImageView(image.view, null);
}

fn hasStencilComponent(format: vk.Format) bool {
    return format == .d32_sfloat_s8_uint or format == .d24_unorm_s8_uint or format == .d16_unorm_s8_uint;
}

pub fn transitionImageLayout(gc: *const GraphicsContext, cmdpool: vk.CommandPool, from: vk.ImageLayout, to: vk.ImageLayout, image: vk.Image, image_format: vk.Format) !void {
    const cmdbuf = try beginOneTimeCommandBuffer(gc, cmdpool);

    var barrier = vk.ImageMemoryBarrier{
        .old_layout = from,
        .new_layout = to,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresource_range = .{
            .aspect_mask = undefined,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .src_access_mask = undefined,
        .dst_access_mask = undefined,
    };

    if (to == .depth_stencil_attachment_optimal) {
        barrier.subresource_range.aspect_mask = .{ .depth_bit = true };
        if (hasStencilComponent(image_format)) {
            barrier.subresource_range.aspect_mask.stencil_bit = true;
        }
    } else {
        barrier.subresource_range.aspect_mask = .{ .color_bit = true };
    }

    var src_stage: vk.PipelineStageFlags = undefined;
    var dst_stage: vk.PipelineStageFlags = undefined;
    if (from == .undefined and to == .transfer_dst_optimal) {
        barrier.src_access_mask = .{};
        barrier.dst_access_mask = .{ .transfer_write_bit = true };

        src_stage = .{ .top_of_pipe_bit = true };
        dst_stage = .{ .transfer_bit = true };
    } else if (from == .transfer_dst_optimal and to == .shader_read_only_optimal) {
        barrier.src_access_mask = .{ .transfer_write_bit = true };
        barrier.dst_access_mask = .{ .shader_read_bit = true };

        src_stage = .{ .transfer_bit = true };
        dst_stage = .{ .fragment_shader_bit = true };
    } else if (from == .undefined and to == .depth_stencil_attachment_optimal) {
        barrier.src_access_mask = .{};
        barrier.dst_access_mask = .{ .depth_stencil_attachment_read_bit = true, .depth_stencil_attachment_write_bit = true };

        src_stage = .{ .top_of_pipe_bit = true };
        dst_stage = .{ .early_fragment_tests_bit = true };
    } else if (from == .undefined and to == .transfer_src_optimal) {
        barrier.src_access_mask = .{};
        barrier.dst_access_mask = .{ .transfer_read_bit = true };

        src_stage = .{ .top_of_pipe_bit = true };
        dst_stage = .{ .transfer_bit = true };
    } else {
        return error.UnsupportedLayoutTransition;
    }

    gc.dev.cmdPipelineBarrier(cmdbuf, src_stage, dst_stage, .{}, 0, null, 0, null, 1, @ptrCast(&barrier));

    try endOneTimeCommandBuffer(gc, cmdpool, cmdbuf);
}

pub const Buffer = struct {
    size: vk.DeviceSize,
    buffer: vk.Buffer,
    mem: vk.DeviceMemory,

    pub fn map(self: *const Buffer, gc: *const GraphicsContext) !?*anyopaque {
        return gc.dev.mapMemory(self.mem, 0, self.size, .{});
    }
};

pub fn createBuffer(gc: *const GraphicsContext, size: vk.DeviceSize, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags) !Buffer {
    const buffer = try gc.dev.createBuffer(&.{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
    }, null);

    const mem_reqs = gc.dev.getBufferMemoryRequirements(buffer);
    const mem = try gc.dev.allocateMemory(&.{
        .allocation_size = mem_reqs.size,
        .memory_type_index = try findMemoryTypeIndex(gc, mem_reqs.memory_type_bits, properties),
    }, null);

    try gc.dev.bindBufferMemory(buffer, mem, 0);

    return .{
        .size = size,
        .buffer = buffer,
        .mem = mem,
    };
}

pub fn copyBuffer(gc: *const GraphicsContext, cmdpool: vk.CommandPool, src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize) !void {
    const cmdbuf = try beginOneTimeCommandBuffer(gc, cmdpool);

    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    gc.dev.cmdCopyBuffer(cmdbuf, src, dst, 1, @ptrCast(&region));

    try endOneTimeCommandBuffer(gc, cmdpool, cmdbuf);
}

pub fn copyBufferToImage(gc: *const GraphicsContext, cmdpool: vk.CommandPool, src: vk.Buffer, dst: vk.Image, width: u32, height: u32) !void {
    const cmdbuf = try beginOneTimeCommandBuffer(gc, cmdpool);

    const region = vk.BufferImageCopy{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{ .width = width, .height = height, .depth = 1 },
    };
    gc.dev.cmdCopyBufferToImage(cmdbuf, src, dst, .transfer_dst_optimal, 1, @ptrCast(&region));

    try endOneTimeCommandBuffer(gc, cmdpool, cmdbuf);
}

pub fn copyImageToBuffer(gc: *const GraphicsContext, cmdpool: vk.CommandPool, src: vk.Image, dst: vk.Buffer, width: u32, height: u32) !void {
    const cmdbuf = try beginOneTimeCommandBuffer(gc, cmdpool);

    const region = vk.BufferImageCopy{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{ .width = width, .height = height, .depth = 1 },
    };
    gc.dev.cmdCopyImageToBuffer(cmdbuf, src, .transfer_src_optimal, dst, 1, @ptrCast(&region));

    try endOneTimeCommandBuffer(gc, cmdpool, cmdbuf);
}

pub fn destroyBuffer(gc: *const GraphicsContext, buffer: Buffer) void {
    gc.dev.destroyBuffer(buffer.buffer, null);
    gc.dev.freeMemory(buffer.mem, null);
}
