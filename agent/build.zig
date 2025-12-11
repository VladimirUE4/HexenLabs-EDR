const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "hexen-agent",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    // Add embedded osquery binary
    exe.addAnonymousModule("osquery", .{
        .root_source_file = b.path("src/osquery.zig"),
    });
    
    exe.addAnonymousModule("config", .{
        .root_source_file = b.path("src/config.zig"),
    });
    
    exe.addAnonymousModule("validation", .{
        .root_source_file = b.path("src/validation.zig"),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the agent");
    run_step.dependOn(&run_cmd.step);
}
