const std = @import("std");
const za = @import("zalgebra");
const Key = @import("term/key.zig").Key;

pub const Camera = struct {
    fovy_degrees: f32 = 70,
    aspect: f32,
    near: f32 = 0.1,
    far: f32 = 100,
    transform: za.Mat4 = .{
        .data = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, -1, 0 },
            .{ 0, 0, 5, 1 },
        },
    },
    _transform2: za.Mat4 = za.Mat4.identity(),

    pub fn getProjViewMatrix(camera: *const Camera) za.Mat4 {
        const f = 1.0 / @tan(za.toRadians(camera.fovy_degrees) * 0.5);
        const x = 1.0 / (camera.far - camera.near);
        const proj = za.Mat4{
            .data = .{
                .{ f / camera.aspect, 0, 0, 0 },
                .{ 0, -f, 0, 0 },
                .{ 0, 0, (camera.far + camera.near) * x, 1 },
                .{ 0, 0, -2 * camera.far * camera.near * x, 0 },
            },
        };

        return proj.mul(camera.transform.mul(camera._transform2).inv());
    }

    pub fn handleInput(cam: *Camera, key: Key) void {
        const speed = 0.1;

        if (key.getch() == 'w') {
            const pos = za.Vec4.fromSlice(&cam.transform.data[3]);
            const dir = za.Vec4.fromSlice(&cam.transform.data[2]);
            cam.transform.data[3] = pos.add(dir.mul(za.Vec4.set(speed))).data;
        } else if (key.getch() == 's') {
            const pos = za.Vec4.fromSlice(&cam.transform.data[3]);
            const dir = za.Vec4.fromSlice(&cam.transform.data[2]);
            cam.transform.data[3] = pos.sub(dir.mul(za.Vec4.set(speed))).data;
        } else if (key.getch() == 'a') {
            const pos = za.Vec4.fromSlice(&cam.transform.data[3]);
            const dir = za.Vec4.fromSlice(&cam.transform.data[0]);
            cam.transform.data[3] = pos.sub(dir.mul(za.Vec4.set(speed))).data;
        } else if (key.getch() == 'd') {
            const pos = za.Vec4.fromSlice(&cam.transform.data[3]);
            const dir = za.Vec4.fromSlice(&cam.transform.data[0]);
            cam.transform.data[3] = pos.add(dir.mul(za.Vec4.set(speed))).data;
        } else if (key.getch() == 'q') {
            const pos = za.Vec4.fromSlice(&cam.transform.data[3]);
            const dir = za.Vec4.fromSlice(&cam.transform.data[1]);
            cam.transform.data[3] = pos.sub(dir.mul(za.Vec4.set(speed))).data;
        } else if (key.getch() == 'e') {
            const pos = za.Vec4.fromSlice(&cam.transform.data[3]);
            const dir = za.Vec4.fromSlice(&cam.transform.data[1]);
            cam.transform.data[3] = pos.add(dir.mul(za.Vec4.set(speed))).data;
        } else if (key.getch() == 'h' or key == .left) {
            cam.transform = cam.transform.rotate(-5, za.Vec3.fromSlice(&cam.transform.data[1]));
        } else if (key.getch() == 'l' or key == .right) {
            cam.transform = cam.transform.rotate(5, za.Vec3.fromSlice(&cam.transform.data[1]));
        } else if (key.getch() == 'j' or key == .down) {
            cam._transform2 = cam._transform2.rotate(5, za.Vec3.new(1, 0, 0));
        } else if (key.getch() == 'k' or key == .up) {
            cam._transform2 = cam._transform2.rotate(-5, za.Vec3.new(1, 0, 0));
        }
    }
};
