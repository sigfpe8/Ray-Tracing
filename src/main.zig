const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Reader = Io.Reader;
const Writer = Io.Writer;

const mth = @import("math.zig");
const Vector = mth.Vector;
const Matrix = mth.Matrix;
const Point = mth.Point;
const vector = mth.vector;
const point = mth.point;

const dem = @import("demo.zig");
const DemoOptions = dem.DemoOptions;
const renderDemo = dem.renderDemo;

const sio = @import("stdio.zig");
const printErr = sio.printErr;

const yml = @import("yaml.zig");
const renderYaml = yml.renderYaml;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    // Initialize stdio
    sio.init(io);

    var options = DemoOptions{};
    const n = parseOptions(args, &options);

    if (options.name != null) {
        // Render predefined demo scene
        try renderDemo(io, arena, &options);        
    } else {
        // Skip first n arguments (including first one = program name)
        // The remaining arguments must be YAML files to be rendered
        for (args[n..]) |arg| {
            try renderYaml(io, arena, arg);
        }
    }
}

fn parseOptions(args: []const [:0]const u8, options: *DemoOptions) usize {
    var n: usize = 1;
    const len = args.len;

    while (n < len) : (n += 1) {
        const arg = args[n];
        if (std.mem.eql(u8, arg, "--help")) {
            printUsage(args[0]);
        }
        if (std.mem.eql(u8, arg, "-d")) {
            n += 1;
            options.name = getString(args, n, "-d");
            continue;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--height")) {
            n += 1;
            options.height = getUint(args, n, "-h");
            continue;
        }
        if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--width")) {
            n += 1;
            options.width = getUint(args, n, "-w");
            continue;
        }
        if (std.mem.eql(u8, arg, "-j") or std.mem.eql(u8, arg, "--threads")) {
            n += 1;
            options.threads = getUint(args, n, "-j");
            continue;
        }
        // Reached the end of the options?
        if (arg[0] == '-') {
            printErr("Invalid option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            // Yes
            break;
        }
    }
    return n;
}

fn printUsage(pgm: [:0]const u8) void {
    printErr("\nYou can use {s} to render predefined demo scenes or read\n", .{pgm});
    printErr("scene descriptions from files in YAML format.\n\n", .{});
    printErr("{s} <options> <file.yml>...\n", .{pgm});
    printErr("options: --help        print help\n", .{});
    printErr("         -d <name>     demo name\n", .{});
    printErr("         -h <n>        canvas height in pixels for demo scene\n", .{});
    // printErr("         --height <n>\n", .{});
    printErr("         -w <n>        canvas width in pixels for demo scene\n", .{});
    // printErr("         --width <n>\n", .{});
    printErr("         -j <n>        number of threads to render demo\n", .{});

    std.process.exit(1);
}

fn getUint(args: []const [:0]const u8, n: usize, opt: [:0]const u8) usize {
    if (n >= args.len) {
        printErr("Missing numeric parameter for {s}\n", .{opt});
        std.process.exit(1);
    }

    const v = std.fmt.parseUnsigned(usize, args[n], 10) catch {
        printErr("Invalid numeric parameter for {s}\n", .{opt});
        std.process.exit(1);    
    };

    return v;
}

fn getString(args: []const [:0]const u8, n: usize, opt: [:0]const u8) []const u8 {
    if (n >= args.len) {
        printErr("Missing string parameter for {s}\n", .{opt});
        std.process.exit(1);
    }

    return args[n];
}
