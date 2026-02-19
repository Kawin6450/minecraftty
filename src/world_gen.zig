const std = @import("std");
const za = @import("zalgebra");
const perlin = @import("perlin.zig");
const Geometry = @import("geometry.zig").Geometry;
const Vertex = @import("geometry.zig").Vertex;
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const vk = @import("vulkan");

pub const BlockType = enum {
    Grass,
    Dirt,
    Stone,
};

pub const Block = struct {
    pos: za.Vec3,
    type: BlockType,
};

pub const chunk_size = 8;
pub const chunk_height = 8;

pub fn generate_chunk(alloc: std.mem.Allocator, chunk_pos: za.Vec2) ![][][]Block {
    const actual_chunk_pos = za.Vec3.new(chunk_pos.x() * chunk_size, 0, chunk_pos.y() * chunk_size);

    var chunk = try alloc.alloc([][]Block, chunk_height);

    for (0..chunk_size) |x| {
        const row = try alloc.alloc([]Block, chunk_size);
        chunk.ptr[x] = row;

        for (0..chunk_size) |z| {
            const height = (@abs(perlin.noise(f32, perlin.Vec(f32){ .x = (@as(f32, @floatFromInt(x)) + 16) / 12, .y = 0, .z = (@as(f32, @floatFromInt(z)) + 12) / 8 })) * 8 + chunk_height);
            var col = try alloc.alloc(Block, @intFromFloat(height));
            row[z] = col;

            for (0..col.len) |y| {
                const pos = actual_chunk_pos.add(za.Vec3.new(@floatFromInt(x), @floatFromInt(y), @floatFromInt(z)));

                const dirt_value = @abs(perlin.noise(f32, perlin.Vec(f32){ .x = pos.x() / 12, .y = pos.y() / 8, .z = pos.z() / 12 }));
                const stone_value = @abs(perlin.noise(f32, perlin.Vec(f32){ .x = (pos.x() + 8) / 12, .y = pos.y() / 8, .z = (pos.z() + 8) / 12 }));
                const block_type = if (dirt_value > 0.2) BlockType.Dirt else if (stone_value > 0.2) BlockType.Stone else BlockType.Grass;

                const block = Block{
                    .pos = pos,
                    .type = block_type,
                };
                col[y] = block;
            }
        }
    }

    return chunk;
}

pub fn generate_chunk_geometry(alloc: std.mem.Allocator, gc: *const GraphicsContext, cmd_pool: vk.CommandPool, chunk_pos: za.Vec2) !Geometry {
    const chunk = try generate_chunk(alloc, chunk_pos);
    defer {
        for (chunk) |layer| {
            for (layer) |row| {
                defer alloc.free(row);
            }
            defer alloc.free(layer);
        }
        defer alloc.free(chunk);
    }

    const grass_side_tc = [4][2]f32{
        .{ 0, 0 },
        .{ 0.5, 0.5 },
        .{ 0, 0.5 },
        .{ 0.5, 0 },
    };
    const grass_top_tc = [4][2]f32{
        .{ 0.5, 0 },
        .{ 1, 0.5 },
        .{ 0.5, 0.5 },
        .{ 1, 0 },
    };
    const stone_tc = [4][2]f32{
        .{ 0, 0.5 },
        .{ 0.5, 1 },
        .{ 0, 1 },
        .{ 0.5, 0.5 },
    };
    const dirt_tc = [4][2]f32{
        .{ 0.5, 0.5 },
        .{ 1, 1 },
        .{ 0.5, 1 },
        .{ 1, 0.5 },
    };

    var chunk_vertices = try std.ArrayList(Vertex).initCapacity(alloc, 4096);
    var chunk_indices = try std.ArrayList(u16).initCapacity(alloc, 4096);
    {
        var i: u16 = 0;
        var j: u16 = 0;
        for (chunk) |layer| {
            for (layer) |row| {
                for (row) |block| {
                    const x = block.pos.x();
                    const y = block.pos.y();
                    const z = block.pos.z();

                    var tex_coords: [24][2]f32 = undefined;
                    switch (block.type) {
                        .Grass => {
                            @memcpy(tex_coords[0..4], &grass_side_tc);
                            @memcpy(tex_coords[4..8], &grass_side_tc);
                            @memcpy(tex_coords[8..12], &grass_side_tc);
                            @memcpy(tex_coords[12..16], &grass_side_tc);
                            @memcpy(tex_coords[16..20], &dirt_tc);
                            @memcpy(tex_coords[20..24], &grass_top_tc);
                        },
                        .Dirt => {
                            @memcpy(tex_coords[0..4], &dirt_tc);
                            @memcpy(tex_coords[4..8], &dirt_tc);
                            @memcpy(tex_coords[8..12], &dirt_tc);
                            @memcpy(tex_coords[12..16], &dirt_tc);
                            @memcpy(tex_coords[16..20], &dirt_tc);
                            @memcpy(tex_coords[20..24], &dirt_tc);
                        },
                        .Stone => {
                            @memcpy(tex_coords[0..4], &stone_tc);
                            @memcpy(tex_coords[4..8], &stone_tc);
                            @memcpy(tex_coords[8..12], &stone_tc);
                            @memcpy(tex_coords[12..16], &stone_tc);
                            @memcpy(tex_coords[16..20], &stone_tc);
                            @memcpy(tex_coords[20..24], &stone_tc);
                        },
                    }

                    const vertices = [_]Vertex{
                        // Front face
                        .{ .pos = .{ x, y + 1, z + 1 }, .color = .{ 1, 0, 0 }, .tex_coord = tex_coords[0] }, // Top left
                        .{ .pos = .{ x + 1, y, z + 1 }, .color = .{ 0, 1, 0 }, .tex_coord = tex_coords[1] }, // Bottom right
                        .{ .pos = .{ x, y, z + 1 }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[2] }, // Bottom left
                        .{ .pos = .{ x + 1, y + 1, z + 1 }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[3] }, // Top right
                        // Back face
                        .{ .pos = .{ x, y + 1, z }, .color = .{ 1, 0, 0 }, .tex_coord = tex_coords[4] },
                        .{ .pos = .{ x + 1, y, z }, .color = .{ 0, 1, 0 }, .tex_coord = tex_coords[5] },
                        .{ .pos = .{ x, y, z }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[6] },
                        .{ .pos = .{ x + 1, y + 1, z }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[7] },
                        // Left face
                        .{ .pos = .{ x, y + 1, z }, .color = .{ 1, 0, 0 }, .tex_coord = tex_coords[8] },
                        .{ .pos = .{ x, y, z + 1 }, .color = .{ 0, 1, 0 }, .tex_coord = tex_coords[9] },
                        .{ .pos = .{ x, y, z }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[10] },
                        .{ .pos = .{ x, y + 1, z + 1 }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[11] },
                        // Right face
                        .{ .pos = .{ x + 1, y + 1, z }, .color = .{ 1, 0, 0 }, .tex_coord = tex_coords[12] },
                        .{ .pos = .{ x + 1, y, z + 1 }, .color = .{ 0, 1, 0 }, .tex_coord = tex_coords[13] },
                        .{ .pos = .{ x + 1, y, z }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[14] },
                        .{ .pos = .{ x + 1, y + 1, z + 1 }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[15] },
                        // Bottom face
                        .{ .pos = .{ x, y, z + 1 }, .color = .{ 1, 0, 0 }, .tex_coord = tex_coords[16] },
                        .{ .pos = .{ x + 1, y, z }, .color = .{ 0, 1, 0 }, .tex_coord = tex_coords[17] },
                        .{ .pos = .{ x, y, z }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[18] },
                        .{ .pos = .{ x + 1, y, z + 1 }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[19] },
                        // Top face
                        .{ .pos = .{ x, y + 1, z + 1 }, .color = .{ 1, 0, 0 }, .tex_coord = tex_coords[20] },
                        .{ .pos = .{ x + 1, y + 1, z }, .color = .{ 0, 1, 0 }, .tex_coord = tex_coords[21] },
                        .{ .pos = .{ x, y + 1, z }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[22] },
                        .{ .pos = .{ x + 1, y + 1, z + 1 }, .color = .{ 0, 0, 1 }, .tex_coord = tex_coords[23] },
                    };

                    const indices = [_]u16{
                        // Front face
                        i + 0 + 0,  i + 1 + 0,  i + 2 + 0,
                        i + 0 + 0,  i + 3 + 0,  i + 1 + 0,
                        // Back face
                        i + 2 + 4,  i + 1 + 4,  i + 0 + 4,
                        i + 1 + 4,  i + 3 + 4,  i + 0 + 4,
                        // Left face
                        i + 0 + 8,  i + 1 + 8,  i + 2 + 8,
                        i + 0 + 8,  i + 3 + 8,  i + 1 + 8,
                        // Right face
                        i + 2 + 12, i + 1 + 12, i + 0 + 12,
                        i + 1 + 12, i + 3 + 12, i + 0 + 12,
                        // Bottom face
                        i + 0 + 16, i + 1 + 16, i + 2 + 16,
                        i + 0 + 16, i + 3 + 16, i + 1 + 16,
                        // Top face
                        i + 2 + 20, i + 1 + 20, i + 0 + 20,
                        i + 1 + 20, i + 3 + 20, i + 0 + 20,
                    };

                    try chunk_vertices.appendSlice(alloc, &vertices);
                    try chunk_indices.appendSlice(alloc, &indices);

                    i += 24;
                    j += 36;
                }
            }
        }
    }

    return try Geometry.fromVerticesAndIndices(gc, cmd_pool, try chunk_vertices.toOwnedSlice(alloc), try chunk_indices.toOwnedSlice(alloc));
}
