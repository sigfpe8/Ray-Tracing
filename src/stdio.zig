//! Stdio wrapper functions

const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Reader = Io.Reader;
const Writer = Io.Writer;

var bufinp: [1024]u8 = undefined;
var bufout: [1024]u8 = undefined;
var buferr: [1024]u8 = undefined;

var stdin:  *Reader = undefined;
var stdout: *Writer = undefined;
var stderr: *Writer = undefined;

var stdio_reader: File.Reader = undefined;
var stdio_writer: File.Writer = undefined;
var stdio_error:  File.Writer = undefined;

pub fn init(io: Io) void {
    stdio_reader = .init(.stdin(), io,  &bufinp);
    stdio_writer = .init(.stdout(), io, &bufout);
    stdio_error  = .init(.stderr(), io, &buferr);

    stdin  = &stdio_reader.interface;
    stdout = &stdio_writer.interface;
    stderr = &stdio_error.interface;
}

pub fn printErr(comptime fmt: []const u8, args: anytype) void {
    stderr.print(fmt, args) catch {
        @panic("Error writing to stderr");
    };
    stderr.flush() catch {
        @panic("Error flushing stderr");
    };
}
