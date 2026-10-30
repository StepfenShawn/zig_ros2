const std = @import("std");
const rcl = @import("rcl");
const std_msgs = @import("std_msgs");
const rclallocator = @import("allocator.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const rcl_allocator = try rclallocator.RclAllocator.init(arena);
    defer rcl_allocator.deinit();

    var init_options = rcl.rcl_get_zero_initialized_init_options();
    var ret = rcl.rcl_init_options_init(&init_options, rcl_allocator.c_allocator);
    if (ret != rcl.RCL_RET_OK)
        return error.RclInitOptionsFailed;

    var context = rcl.rcl_get_zero_initialized_context();
    ret = rcl.rcl_init(0, null, &init_options, &context);
    if (ret != rcl.RCL_RET_OK)
        return error.RclInitFailed;
    defer _ = rcl.rcl_shutdown(&context);
    var node = rcl.rcl_get_zero_initialized_node();
    var node_options = rcl.rcl_node_get_default_options();
    ret = rcl.rcl_node_init(&node, "zig_talker", "/", &context, &node_options);
    if (ret != rcl.RCL_RET_OK)
        return error.NodeInitFailed;
    defer _ = rcl.rcl_node_fini(&node);

    var publisher = rcl.rcl_get_zero_initialized_publisher();
    var publisher_options = rcl.rcl_publisher_get_default_options();

    const type_support = std_msgs.rosidl_typesupport_c__get_message_type_support_handle__std_msgs__msg__String();

    ret = rcl.rcl_publisher_init(&publisher, &node, @ptrCast(type_support), "/chatter", &publisher_options);
    if (ret != rcl.RCL_RET_OK) return error.PublisherInitFailed;
    defer _ = rcl.rcl_publisher_fini(&publisher, &node);

    var count: usize = 0;
    while (count < 10) : (count += 1) {
        var msg: std_msgs.struct_std_msgs__msg__String = undefined;
        _ = std_msgs.std_msgs__msg__String__init(&msg);
        const text = "Hello from Zig!";
        _ = std_msgs.rosidl_runtime_c__String__assign(&msg.data, text.ptr);
        ret = rcl.rcl_publish(&publisher, @ptrCast(&msg), null);
        if (ret != rcl.RCL_RET_OK) {
            std.debug.print("Failed to publish message.\n", .{});
        } else {
            std.debug.print("Published message #{d}\n", .{count});
        }
        try std.Io.sleep(io, std.Io.Duration.fromSeconds(1), .awake);
    }
}
