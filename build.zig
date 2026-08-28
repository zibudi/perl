const std = @import("std");

pub fn build(b: *std.Build) void {
    const host = b.graph.host;

    const source = b.dependency("perl_source", .{});
    const make = b.dependency("gnumake", .{ .target = host, .optimize = .ReleaseFast });
    const binutils = b.dependency("binutils", .{ .target = host, .optimize = .ReleaseFast });
    const busybox = b.dependency("busybox", .{ .target = host, .optimize = .ReleaseSmall });

    // Configure records nm and the Makefile archives with ar. busybox has an ar
    // that only reads archives, so both come from binutils.
    const bin = b.addWriteFiles();
    _ = bin.addCopyFile(make.artifact("make").getEmittedBin(), "make");
    for ([_][]const u8{ "ar", "nm" }) |name| {
        _ = bin.addCopyFile(binutils.artifact(name).getEmittedBin(), name);
    }

    // busybox dispatches on argv[0], and it is the one that knows which names it
    // answers to. Copied and linked to relatively, so the directory relocates.
    const link = b.addRunArtifact(busybox.artifact("busybox"));
    link.addArgs(&.{
        "sh",
        "-c",
        \\"$1" cp "$1" "$2/busybox"
        \\for applet in $("$1" --list); do "$1" ln -sf busybox "$2/$applet"; done
        ,
        "--",
    });
    link.addArtifactArg(busybox.artifact("busybox"));
    const applets = link.addOutputDirectoryArg("applets");

    const configure = b.addRunArtifact(b.addExecutable(.{
        .name = "configure",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/perl.zig"),
            .target = host,
            .optimize = .ReleaseFast,
        }),
    }));
    configure.addDirectoryArg(bin.getDirectory());
    configure.addDirectoryArg(applets);
    configure.addDirectoryArg(source.path("."));
    configure.addArg(b.graph.zig_exe);
    const out = configure.addOutputDirectoryArg("perl");

    b.addNamedLazyPath("perl", out);

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = out,
        .install_dir = .prefix,
        .install_subdir = ".",
    }).step);
}
