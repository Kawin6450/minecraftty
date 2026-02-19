const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Build step

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe_mod = b.addModule("minecraftty", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "minecraftty",
        .root_module = exe_mod,
    });

    var env_map = try std.process.getEnvMap(b.allocator);
    defer env_map.deinit();
    var sdk_path: ?[]const u8 = null;
    if (env_map.get("VULKAN_SDK")) |_sdk_path| {
        sdk_path = _sdk_path;

        std.debug.print("Found Vulkan SDK: {s}\n", .{_sdk_path});

        const lib_path = b.pathJoin(&.{ _sdk_path, "lib" });
        const include_path = b.pathJoin(&.{ _sdk_path, "include" });

        exe.addLibraryPath(.{ .cwd_relative = lib_path });
        exe.addIncludePath(.{ .cwd_relative = include_path });

        std.debug.print("Added library path: {s}\n", .{lib_path});
        std.debug.print("Added include path: {s}\n", .{include_path});
    }

    const vk_lib_name = if (target.result.os.tag == .windows) "vulkan-1" else "vulkan";
    exe.linkSystemLibrary(vk_lib_name);

    try compileShaders(b, exe, sdk_path);

    b.installArtifact(exe);

    const options = b.addOptions();
    options.addOption([]const u8, "name", "minecraftty");
    exe.root_module.addImport("config", options.createModule());

    const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    const vulkan = b.dependency("vulkan", .{
        .registry = registry,
    }).module("vulkan-zig");
    const zalgebra = b.dependency("zalgebra", .{}).module("zalgebra");
    const zigimg = b.dependency("zigimg", .{}).module("zigimg");
    exe.root_module.addImport("vulkan", vulkan);
    exe.root_module.addImport("zalgebra", zalgebra);
    exe.root_module.addImport("zigimg", zigimg);

    // Check step

    const exe_check = b.addExecutable(.{
        .name = "minecraftty",
        .root_module = exe_mod,
    });
    const check_step = b.step("check", "Check if it compiles");
    check_step.dependOn(&exe_check.step);

    // Run step

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run it");
    run_step.dependOn(&run_cmd.step);
}

fn compileShaders(b: *std.Build, exe: *std.Build.Step.Compile, sdk_path: ?[]const u8) !void {
    const glslc_exe_path = if (sdk_path) |_sdk_path|
        b.pathJoin(&.{ _sdk_path, "bin", "glslc" })
    else
        "glslc";

    const vert_cmd = b.addSystemCommand(&.{ glslc_exe_path, "-o" });
    const vert_spv = vert_cmd.addOutputFileArg("vert.spv");
    vert_cmd.addFileArg(b.path("shaders/triangle.vert"));
    exe.step.dependOn(&vert_cmd.step);
    exe.root_module.addAnonymousImport("vertex_shader", .{
        .root_source_file = vert_spv,
    });

    const frag_cmd = b.addSystemCommand(&.{ glslc_exe_path, "-o" });
    const frag_spv = frag_cmd.addOutputFileArg("frag.spv");
    frag_cmd.addFileArg(b.path("shaders/triangle.frag"));
    exe.step.dependOn(&frag_cmd.step);
    exe.root_module.addAnonymousImport("fragment_shader", .{
        .root_source_file = frag_spv,
    });
}
