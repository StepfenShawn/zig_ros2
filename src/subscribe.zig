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
    ret = rcl.rcl_node_init(&node, "zig_listener", "/", &context, &node_options);
    if (ret != rcl.RCL_RET_OK)
        return error.NodeInitFailed;
    defer _ = rcl.rcl_node_fini(&node);

    var subscription = rcl.rcl_get_zero_initialized_subscription();
    var sub_options = rcl.rcl_subscription_get_default_options();

    const type_support = std_msgs.rosidl_typesupport_c__get_message_type_support_handle__std_msgs__msg__String();
    ret = rcl.rcl_subscription_init(
        &subscription,
        &node,
        @ptrCast(type_support),
        "/chatter",
        &sub_options,
    );
    if (ret != rcl.RCL_RET_OK) return error.SubscriptionInitFailed;
    defer _ = rcl.rcl_subscription_fini(&subscription, &node);

    std.debug.print("Listener started, waiting for messages on '/chatter'...\n", .{});
    while (true) {
        var msg: std_msgs.struct_std_msgs__msg__String = undefined;
        _ = std_msgs.std_msgs__msg__String__init(&msg);
        defer std_msgs.std_msgs__msg__String__fini(&msg);

        ret = rcl.rcl_take(&subscription, @ptrCast(&msg), null, null);
        if (ret == rcl.RCL_RET_OK) {
            const received_str = std.mem.span(msg.data.data);
            std.debug.print("I heard: {s}\n", .{received_str});
        } else if (ret == rcl.RCL_RET_SUBSCRIPTION_TAKE_FAILED) {
            try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(100), .awake);
        } else {
            std.debug.print("Failed to take message, error code: {d}\n", .{ret});
        }
    }
}
