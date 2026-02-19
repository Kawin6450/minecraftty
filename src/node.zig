const za = @import("zalgebra");
const Geometry = @import("geometry.zig").Geometry;
const Material = @import("material.zig").Material;

pub const Node = struct {
    geometry: Geometry,
    material: Material,
    transform: za.Mat4,
};
