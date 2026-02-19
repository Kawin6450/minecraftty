const config = @import("config");
const std = @import("std");
const vk = @import("vulkan");
const vku = @import("vkutils.zig");
const Terminal = @import("terminal.zig").Terminal;
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Allocator = std.mem.Allocator;
const Camera = @import("camera.zig").Camera;
const Vertex = @import("geometry.zig").Vertex;
const Geometry = @import("geometry.zig").Geometry;
const Material = @import("material.zig").Material;
const Node = @import("node.zig").Node;
const za = @import("zalgebra");
const wg = @import("world_gen.zig");

pub const Minecraftty = struct {
    const format = vk.Format.r8g8b8a8_unorm;
    const depth_format = vk.Format.d24_unorm_s8_uint;

    alloc: Allocator,

    cam: *Camera,
    scene: std.ArrayList(Node),

    extent: vk.Extent2D,
    gc: GraphicsContext,
    cmdpool: vk.CommandPool,

    image: ?vku.Image,
    depth_image: ?vku.Image,
    framebuffer: ?vk.Framebuffer,

    cmdbuf: vk.CommandBuffer,
    render_pass: vk.RenderPass,
    fence: vk.Fence,

    image_buf: ?vku.Buffer,
    image_buf_m: ?[*]u8,
    t: Terminal,

    pub fn init(alloc: std.mem.Allocator, cam: *Camera) !Minecraftty {
        var mc: Minecraftty = undefined;

        mc.alloc = alloc;

        mc.cam = cam;
        mc.scene = try .initCapacity(alloc, 4);

        mc.extent = vk.Extent2D{ .width = 0, .height = 0 };

        mc.gc = try GraphicsContext.init(alloc, @ptrCast(&config.name));
        std.log.debug("Using device: {s}", .{mc.gc.deviceName()});

        mc.cmdpool = try mc.gc.dev.createCommandPool(&.{
            .queue_family_index = mc.gc.graphics_queue.family,
            .flags = .{ .reset_command_buffer_bit = true },
        }, null);

        try mc.gc.dev.allocateCommandBuffers(&.{
            .command_pool = mc.cmdpool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&mc.cmdbuf));

        try mc.createRenderPass();

        mc.fence = try mc.gc.dev.createFence(&.{}, null);

        mc.image = null;
        mc.depth_image = null;
        mc.framebuffer = null;

        mc.image_buf = null;
        mc.image_buf_m = null;
        mc.t = try Terminal.init();

        return mc;
    }

    fn createRenderPass(mc: *Minecraftty) !void {
        const color_attachment = vk.AttachmentDescription{
            .format = format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .color_attachment_optimal,
        };
        const depth_attachment = vk.AttachmentDescription{
            .format = depth_format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .dont_care,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .depth_stencil_attachment_optimal,
        };

        const color_attachment_ref = vk.AttachmentReference{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        };
        const depth_attachment_ref = vk.AttachmentReference{
            .attachment = 1,
            .layout = .depth_stencil_attachment_optimal,
        };

        const subpass = vk.SubpassDescription{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&color_attachment_ref),
            .p_depth_stencil_attachment = @ptrCast(&depth_attachment_ref),
        };

        const attachments = [_]vk.AttachmentDescription{ color_attachment, depth_attachment };
        const dependency = vk.SubpassDependency{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true },
            .src_access_mask = .{},
            .dst_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true },
            .dst_access_mask = .{ .color_attachment_write_bit = true, .depth_stencil_attachment_write_bit = true },
        };
        mc.render_pass = try mc.gc.dev.createRenderPass(&.{
            .attachment_count = attachments.len,
            .p_attachments = &attachments,
            .subpass_count = 1,
            .p_subpasses = @ptrCast(&subpass),
            .dependency_count = 1,
            .p_dependencies = @ptrCast(&dependency),
        }, null);
    }

    pub fn deinit(mc: *Minecraftty) void {
        mc.t.deinit();
        if (mc.image_buf) |image_buf| {
            mc.gc.dev.unmapMemory(image_buf.mem);
            vku.destroyBuffer(&mc.gc, image_buf);
        }
        if (mc.framebuffer) |fb| {
            mc.gc.dev.destroyFramebuffer(fb, null);
        }
        if (mc.image) |image| {
            vku.destroyImage(&mc.gc, image);
        }
        if (mc.depth_image) |image| {
            vku.destroyImage(&mc.gc, image);
        }
        mc.gc.dev.destroyFence(mc.fence, null);
        mc.gc.dev.destroyRenderPass(mc.render_pass, null);
        mc.gc.dev.freeCommandBuffers(mc.cmdpool, 1, @ptrCast(&mc.cmdbuf));
        mc.gc.dev.destroyCommandPool(mc.cmdpool, null);
        mc.gc.deinit();
        mc.scene.deinit(mc.alloc);
    }

    fn checkTermSize(mc: *Minecraftty) !void {
        //const termSize = try t.getSize();
        const termSize = .{ .w = 100, .h = 60 };
        const extent = vk.Extent2D{ .width = termSize.w, .height = termSize.h };

        if (std.meta.eql(extent, mc.extent)) {
            return;
        }

        mc.extent = extent;

        mc.cam.aspect = @as(f32, @floatFromInt(extent.width)) / @as(f32, @floatFromInt(extent.height));

        if (mc.framebuffer) |fb| {
            mc.gc.dev.destroyFramebuffer(fb, null);
        }
        if (mc.image) |image| {
            vku.destroyImage(&mc.gc, image);
        }
        if (mc.depth_image) |image| {
            vku.destroyImage(&mc.gc, image);
        }

        mc.image = try vku.createImage(
            &mc.gc,
            format,
            extent.width,
            extent.height,
            .optimal,
            .{ .transfer_src_bit = true, .color_attachment_bit = true },
            .{ .device_local_bit = true },
            .{ .color_bit = true },
        );

        mc.depth_image = try vku.createImage(
            &mc.gc,
            depth_format,
            extent.width,
            extent.height,
            .optimal,
            .{ .depth_stencil_attachment_bit = true },
            .{ .device_local_bit = true },
            .{ .depth_bit = true },
        );

        const framebuffer_attachments = [_]vk.ImageView{ mc.image.?.view, mc.depth_image.?.view };
        mc.framebuffer = try mc.gc.dev.createFramebuffer(&.{
            .render_pass = mc.render_pass,
            .attachment_count = framebuffer_attachments.len,
            .p_attachments = &framebuffer_attachments,
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        }, null);

        mc.image_buf = try vku.createBuffer(
            &mc.gc,
            8 * mc.extent.width * mc.extent.height,
            .{ .transfer_dst_bit = true, .storage_buffer_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );

        mc.image_buf_m = @ptrCast(@alignCast(try mc.gc.dev.mapMemory(mc.image_buf.?.mem, 0, vk.WHOLE_SIZE, .{})));
    }

    pub fn render(mc: *Minecraftty) !void {
        try mc.checkTermSize();

        // Fill command buffer
        try mc.gc.dev.resetCommandBuffer(mc.cmdbuf, .{});
        const ctx = CommandBufferContext{
            .render_pass = mc.render_pass,
            .framebuffer = mc.framebuffer.?,
            .extent = mc.extent,
        };
        try mc.beginCommandBuffer(ctx);
        for (mc.scene.items) |*node| {
            try node.material.recordCommandBuffer(&mc.gc, mc.cmdbuf, node, mc.cam);
        }
        try mc.endCommandBuffer();

        // Submit command buffer
        const submit_info = vk.SubmitInfo{
            .p_wait_dst_stage_mask = &.{.{ .color_attachment_output_bit = true }},
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&mc.cmdbuf),
        };
        try mc.gc.dev.queueSubmit(mc.gc.graphics_queue.handle, 1, @ptrCast(&submit_info), mc.fence);

        // Wait for fences
        _ = try mc.gc.dev.waitForFences(1, @ptrCast(&mc.fence), .true, std.math.maxInt(u64));
        _ = try mc.gc.dev.resetFences(1, @ptrCast(&mc.fence));

        try mc.present();
    }

    pub const CommandBufferContext = struct {
        render_pass: vk.RenderPass,
        framebuffer: vk.Framebuffer,
        extent: vk.Extent2D,
    };

    fn beginCommandBuffer(mc: *Minecraftty, ctx: CommandBufferContext) !void {
        try mc.gc.dev.beginCommandBuffer(mc.cmdbuf, &.{});

        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(ctx.extent.width),
            .height = @floatFromInt(ctx.extent.height),
            .min_depth = 0,
            .max_depth = 1,
        };
        const scissor = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = ctx.extent,
        };
        mc.gc.dev.cmdSetViewport(mc.cmdbuf, 0, 1, @ptrCast(&viewport));
        mc.gc.dev.cmdSetScissor(mc.cmdbuf, 0, 1, @ptrCast(&scissor));

        const clear_values = [_]vk.ClearValue{
            .{ .color = .{ .float_32 = .{ 0.4, 0.7, 1, 1.0 } } },
            .{ .depth_stencil = .{ .depth = 1, .stencil = 0 } },
        };
        mc.gc.dev.cmdBeginRenderPass(mc.cmdbuf, &.{
            .render_pass = ctx.render_pass,
            .framebuffer = ctx.framebuffer,
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = ctx.extent,
            },
            .clear_value_count = clear_values.len,
            .p_clear_values = &clear_values,
        }, .@"inline");
    }

    fn endCommandBuffer(mc: *Minecraftty) !void {
        mc.gc.dev.cmdEndRenderPass(mc.cmdbuf);

        try mc.gc.dev.endCommandBuffer(mc.cmdbuf);
    }

    fn present(mc: *Minecraftty) !void {
        try vku.transitionImageLayout(&mc.gc, mc.cmdpool, .undefined, .transfer_src_optimal, mc.image.?.image, format);
        try vku.copyImageToBuffer(&mc.gc, mc.cmdpool, mc.image.?.image, mc.image_buf.?.buffer, mc.extent.width, mc.extent.height);

        // Reset cursor position
        try mc.t.backend.setCursorPos(0, 0);

        // Print the pixels
        var prev_color1: ?[3]u8 = null;
        var prev_color2: ?[3]u8 = null;
        var y: u32 = 0;
        while (y < mc.extent.height) {
            var x: u32 = 0;
            while (x < mc.extent.width) {
                // Alpha channel is skipped

                var j = (y * mc.extent.width + x) * 4;
                const c1 = [_]u8{ mc.image_buf_m.?[j], mc.image_buf_m.?[j + 1], mc.image_buf_m.?[j + 2] };

                j = ((y + 1) * mc.extent.width + x) * 4;
                const c2 = [_]u8{ mc.image_buf_m.?[j], mc.image_buf_m.?[j + 1], mc.image_buf_m.?[j + 2] };

                if (prev_color1 == null or std.mem.eql(u8, &prev_color1.?, &c1) == false or
                    prev_color2 == null or std.mem.eql(u8, &prev_color2.?, &c2) == false)
                {
                    try mc.t.backend.setForeground(c1);
                    try mc.t.backend.setBackground(c2);

                    prev_color1 = c1;
                    prev_color2 = c2;
                }

                try mc.t.backend.writeAll("▀");

                x += 1;
            }

            try mc.t.backend.writeAll("\n");
            y += 2;
        }

        try mc.t.backend.flush();
    }
};
