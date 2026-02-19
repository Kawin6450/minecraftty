const std = @import("std");
const Minecraftty = @import("minecraftty.zig").Minecraftty;
const Camera = @import("camera.zig").Camera;
const Geometry = @import("geometry.zig").Geometry;
const Material = @import("material.zig").Material;
const Node = @import("node.zig").Node;
const za = @import("zalgebra");
const wg = @import("world_gen.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var cam = Camera{
        .aspect = 1,
        .transform = .{
            .data = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, -1, 0 },
                .{ 0, 10, 0, 1 },
            },
        },
    };

    var mc = try Minecraftty.init(alloc, &cam);
    defer mc.deinit();

    // Add some stuff to the scene

    var material = try Material.new(alloc, &mc.gc, mc.cmdpool, mc.render_pass);
    defer material.destroy(&mc.gc);

    var chunk1 = Node{
        .geometry = try wg.generate_chunk_geometry(alloc, &mc.gc, mc.cmdpool, za.Vec2.zero()),
        .material = material,
        .transform = za.Mat4.identity(),
    };
    var chunk2 = Node{
        .geometry = try wg.generate_chunk_geometry(alloc, &mc.gc, mc.cmdpool, za.Vec2.new(-1, 0)),
        .material = material,
        .transform = za.Mat4.identity(),
    };
    var chunk3 = Node{
        .geometry = try wg.generate_chunk_geometry(alloc, &mc.gc, mc.cmdpool, za.Vec2.new(0, -1)),
        .material = material,
        .transform = za.Mat4.identity(),
    };
    var chunk4 = Node{
        .geometry = try wg.generate_chunk_geometry(alloc, &mc.gc, mc.cmdpool, za.Vec2.new(-1, -1)),
        .material = material,
        .transform = za.Mat4.identity(),
    };
    defer chunk1.geometry.destroyWithVerticesAndIndices(alloc, &mc.gc);
    defer chunk2.geometry.destroyWithVerticesAndIndices(alloc, &mc.gc);
    defer chunk3.geometry.destroyWithVerticesAndIndices(alloc, &mc.gc);
    defer chunk4.geometry.destroyWithVerticesAndIndices(alloc, &mc.gc);
    try mc.scene.append(alloc, chunk1);
    try mc.scene.append(alloc, chunk2);
    try mc.scene.append(alloc, chunk3);
    try mc.scene.append(alloc, chunk4);

    // Render loop
    while (true) {
        // Handle user input
        const key = try mc.t.backend.readKey();
        if (key.getch() == 'x' or key == .esc) {
            break;
        }
        cam.handleInput(key);

        try mc.render();

        std.Thread.sleep(std.time.ns_per_ms);
    }

    try mc.gc.dev.deviceWaitIdle();
}
