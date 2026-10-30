const std = @import("std");
const rcl = @import("rcl");

pub const RclAllocator = struct {
    c_allocator: rcl.rcl_allocator_t,
    zig_allocator: std.mem.Allocator,
    mem_map: *std.AutoHashMap(usize, usize),

    pub fn init(allocator: std.mem.Allocator) !*RclAllocator {
        const self = try allocator.create(RclAllocator);
        errdefer allocator.destroy(self);

        const mem_map = try allocator.create(std.AutoHashMap(usize, usize));
        errdefer allocator.destroy(mem_map);
        mem_map.* = std.AutoHashMap(usize, usize).init(allocator);

        self.* = .{
            .c_allocator = rcl.rcutils_get_zero_initialized_allocator(),
            .zig_allocator = allocator,
            .mem_map = mem_map,
        };

        self.c_allocator.state = @ptrCast(self);
        self.c_allocator.allocate = rclAllocate;
        self.c_allocator.deallocate = rclDeallocate;
        self.c_allocator.reallocate = rclReallocate;
        self.c_allocator.zero_allocate = rclZeroAllocate;
        return self;
    }

    pub fn deinit(self: *RclAllocator) void {
        self.mem_map.deinit();
        self.zig_allocator.destroy(self.mem_map);
        self.zig_allocator.destroy(self);
    }
};

fn getState(state: ?*anyopaque) *RclAllocator {
    return @ptrCast(@alignCast(state orelse unreachable));
}

fn rclAllocate(size: usize, state: ?*anyopaque) callconv(.c) ?*anyopaque {
    const rcl_allocator = getState(state);
    const result = rcl_allocator.zig_allocator.alloc(u8, size) catch |err| {
        std.log.err("error allocating memory: {s}", .{@errorName(err)});
        return null;
    };
    rcl_allocator.mem_map.put(@intFromPtr(result.ptr), result.len) catch |err| {
        std.log.err("error updating memory map: {s}", .{@errorName(err)});
        rcl_allocator.zig_allocator.free(result);
        return null;
    };
    return result.ptr;
}

fn rclDeallocate(opt_c_pointer: ?*anyopaque, state: ?*anyopaque) callconv(.c) void {
    const rcl_allocator = getState(state);
    if (opt_c_pointer) |c_pointer| {
        const zig_pointer: [*]u8 = @ptrCast(c_pointer);
        const entry = rcl_allocator.mem_map.fetchRemove(@intFromPtr(c_pointer)) orelse unreachable;
        rcl_allocator.zig_allocator.free(zig_pointer[0..entry.value]);
    }
}

fn rclReallocate(opt_c_pointer: ?*anyopaque, size: usize, state: ?*anyopaque) callconv(.c) ?*anyopaque {
    const rcl_allocator = getState(state);
    if (opt_c_pointer) |c_pointer| {
        const zig_pointer: [*]u8 = @ptrCast(c_pointer);
        const old_size = rcl_allocator.mem_map.get(@intFromPtr(c_pointer)) orelse unreachable;
        const result = rcl_allocator.zig_allocator.realloc(zig_pointer[0..old_size], size) catch |err| {
            std.log.err("error during realloc: {s}", .{@errorName(err)});
            return null;
        };
        _ = rcl_allocator.mem_map.remove(@intFromPtr(c_pointer)); // 旧 key 失效
        rcl_allocator.mem_map.put(@intFromPtr(result.ptr), result.len) catch |err| {
            std.log.err("error updating memory map: {s}", .{@errorName(err)});
            rcl_allocator.zig_allocator.free(result);
            return null;
        };
        return result.ptr;
    }
    return null;
}

fn rclZeroAllocate(num_of_elements: usize, size_of_element: usize, state: ?*anyopaque) callconv(.c) ?*anyopaque {
    const num_bytes = num_of_elements * size_of_element;
    const result = rclAllocate(num_bytes, state) orelse return null;
    const ptr: [*]u8 = @ptrCast(result);
    @memset(ptr[0..num_bytes], 0);
    return ptr;
}
