const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdffont_mod = b.addModule("sdffont", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        // .link_libcpp = true,
    });

    const lib_path_string = switch (target.result.os.tag) {
        .windows => "lib/sdffont.dll.lib",
        .linux => "lib/libsdffont.so",
        else => {
            @panic("Only linux and windows are supported. Sorry.");
        },
    };
    const lib_path = b.path(lib_path_string);
    const so_install_file = b.addInstallLibFile(lib_path, "sdffont.so");
    b.getInstallStep().dependOn(&so_install_file.step);
    sdffont_mod.addObjectFile(lib_path);

    sdffont_mod.addLibraryPath(b.path("lib"));
    sdffont_mod.linkSystemLibrary("sdffont", .{});
    sdffont_mod.link_libc = true;

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdffont", .module = sdffont_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
