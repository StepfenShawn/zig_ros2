const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_c = b.dependency("translate_c", .{});
    const rcl_headers = b.addWriteFiles().add("ros2_headers.c",
        \\#include <rcl/rcl.h>
        \\#include <rcutils/allocator.h>
        \\#include <rcl/error_handling.h>
        \\#include <rcl/node.h>
        \\#include <rcl/publisher.h>
    );
    const std_msgs_headers = b.addWriteFiles().add("std_msgs_headers.c",
        \\#include <std_msgs/msg/string.h>
        \\#include <rosidl_runtime_c/string_functions.h>
    );

    const trans_rcl: Translator = .init(translate_c, .{
        .c_source_file = rcl_headers,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_system_libs = &.{
            .{ .name = "rcl" },
        },
    });

    const trans_std_msgs: Translator = .init(translate_c, .{
        .c_source_file = std_msgs_headers,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const ros_include = "/opt/ros/humble/include";
    const io = b.graph.io;
    var include_dir = std.Io.Dir.openDirAbsolute(io, ros_include, .{ .iterate = true }) catch |err| @panic(@errorName(err));
    defer include_dir.close(io);
    var it = include_dir.iterate();
    while (it.next(io) catch |err| @panic(@errorName(err))) |entry| {
        if (entry.kind != .directory) continue;
        const path = std.fs.path.join(b.allocator, &.{ ros_include, entry.name }) catch @panic("OOM");
        trans_rcl.addSystemIncludePath(.{ .cwd_relative = path });
        trans_std_msgs.addSystemIncludePath(.{ .cwd_relative = path });
    }

    const ros_lib = "/opt/ros/humble/lib";
    trans_rcl.mod.addLibraryPath(.{ .cwd_relative = ros_lib });
    trans_rcl.mod.linkSystemLibrary("rcl", .{});
    trans_rcl.mod.linkSystemLibrary("rcutils", .{});

    trans_std_msgs.mod.addLibraryPath(.{ .cwd_relative = ros_lib });
    trans_std_msgs.mod.linkSystemLibrary("std_msgs__rosidl_generator_c", .{});
    trans_std_msgs.mod.linkSystemLibrary("rosidl_runtime_c", .{});
    trans_std_msgs.mod.linkSystemLibrary("std_msgs__rosidl_typesupport_c", .{});

    const rcl_allocator_mod = b.addModule("allocator", .{
        .root_source_file = b.path("src/allocator.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "rcl", .module = trans_rcl.mod },
        },
    });

    const pub_exe = b.addExecutable(.{
        .name = "zig_pub",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/publisher.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "allocator", .module = rcl_allocator_mod },
            },
        }),
    });

    pub_exe.root_module.addLibraryPath(.{ .cwd_relative = ros_lib });
    pub_exe.root_module.addImport("rcl", trans_rcl.mod);
    pub_exe.root_module.addImport("std_msgs", trans_std_msgs.mod);

    const sub_exe = b.addExecutable(.{
        .name = "zig_sub",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/subscribe.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "allocator", .module = rcl_allocator_mod },
            },
        }),
    });

    sub_exe.root_module.addLibraryPath(.{ .cwd_relative = ros_lib });
    sub_exe.root_module.addImport("rcl", trans_rcl.mod);
    sub_exe.root_module.addImport("std_msgs", trans_std_msgs.mod);

    b.installArtifact(pub_exe);
    b.installArtifact(sub_exe);

    const run_cmd = b.addRunArtifact(pub_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
