const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Reader = Io.Reader;
const Allocator = std.mem.Allocator;

const mth = @import("math.zig");
const Float = mth.Float;

const mtl = @import("material.zig");
const Color = mtl.Color;
const black = mtl.black;

pub const Canvas = struct {
    width: usize = undefined,
    height: usize = undefined,
    pixels: []Color = undefined,

    const Self = @This();

    pub fn init(w: usize, h: usize, allocator: Allocator) !Canvas {
        // Allocate the canvas
        const n = w * h;    // Number of cells
        const pixels = try allocator.alloc(Color, n);

        // Clear the canvas
        @memset(pixels, black);

        return Canvas{
            .width = w,
            .height = h,
            .pixels = pixels,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.pixels);
        self.pixels = undefined;
    }

    pub fn writePPM(self: *const Self, io: Io, fname: []const u8) !void {
        var buffer: [1024]u8 = undefined;

        const file = try Io.Dir.cwd().createFile(io, fname, .{});
        defer file.close(io);

        var file_writer: Io.File.Writer = .init(file, io, &buffer);
        var writer = &file_writer.interface;

        try writer.print("P3\n", .{});
        try writer.print("{d} {d}\n", .{self.width, self.height});
        try writer.print("255\n", .{});

        var count: usize = 0;
        var x: u8 = undefined;
        for (self.pixels) |p| {
            x = @intFromFloat(@trunc(@max(0.0, @min(1.0, p[0])) * 255.0));
            try writer.print("{d} ", .{x});

            x = @intFromFloat(@trunc(@max(0.0, @min(1.0, p[1])) * 255.0));
            try writer.print("{d} ", .{x});

            x = @intFromFloat(@trunc(@max(0.0, @min(1.0, p[2])) * 255.0));
            try writer.print("{d} ", .{x});

            count += 1;
            if (count > 6) {
                try writer.print("\n", .{});
                count = 0;
            }
        }
        try writer.flush();
    }
};
