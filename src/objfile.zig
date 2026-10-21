//! Support for reading Wavefront .OBJ files ==================================
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Reader = Io.Reader;

const bvh = @import("bvh.zig");
const BBox = bvh.BBox;

const obi = @import("object.zig");
const Group = obi.Group;
const Object = obi.Object;
const SmoothTriangle = obi.SmoothTriangle;
const Triangle = obi.Triangle;
const group = obi.group;
const smoothTriangle = obi.smoothTriangle;
const triangle = obi.triangle;

const mth = @import("math.zig");
const Float = mth.Float;
const Point = mth.Point;
const Vector = mth.Vector;
const point = mth.point;
const vector = mth.vector;
const INFINITY = mth.INFINITY;

const mtl = @import("material.zig");
const Material = mtl.Material;

const sio = @import("stdio.zig");
const printErr = sio.printErr;

const show_stats = true;

pub const ObjStats = struct {
    lines: usize,       // # of read lines
    ignored: usize,     // # of ignored lines
    vertices: usize,    // # of vertices (v)
    vtextures: usize,   // # of vertex textures (vt)
    vnormals: usize,    // # of vertex normals (vn)
    triangles: usize,   // # of triangles (f with just 3 points)
    polygons: usize,    // # of polygons (f with more than 3 points)
    largest: usize,     // Largest polygon (# of vertices)
    groups: usize,      // # of groups (g)
    objects: usize,     // # of objects (o)
    bytes: usize,       // Memory occupied by group
    x_min: Float,       // Minimum and maximum X coordinates
    x_max: Float,
    y_min: Float,       // Minimum and maximum Y coordinates
    y_max: Float,
    z_min: Float,       // Minimum and maximum Z coordinates
    z_max: Float,
    elapsed: i64,       // elapsed time in milliseconds
};

/// Reads a file in OBJ format and returns the corresponding Object.
pub fn readObjFile(io: Io, allocator: Allocator, fname: []const u8, material: *const Material) !*Object {
    const file = Io.Dir.cwd().openFile(io, fname, .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) {
            printErr("Could not open '{s}'\n", .{fname});
        }
        return err;
    };
    defer file.close(io);
    var buffer: [2048]u8 = undefined;
    var file_reader: Io.File.Reader = .init(file, io, &buffer);
    var ostats: ObjStats = undefined;

    if (show_stats) {
        printErr("\nReading {s}\n", .{fname});
    }

    const start = std.Io.Clock.now(.awake, io);

    const obj = try readObj(allocator, &file_reader.interface, material, &ostats);

    const end = std.Io.Clock.now(.awake, io);
    const dur = start.durationTo(end);
    ostats.elapsed = std.Io.Duration.toMilliseconds(dur);

    if (show_stats) {
        showStats(&ostats);
    }

    return obj;
}

/// Main code for reading OBJ data
fn readObj(allocator: Allocator, r: *Reader, material: *const Material, ostats: *ObjStats) !*Object {
    var vs: std.ArrayList(Point) = .empty;
    var vt: std.ArrayList(Point) = .empty;
    var vn: std.ArrayList(Vector) = .empty;
    var coords: [4]Float = undefined; // Maximum of 4 coordinates per line
    var n_lines: usize = 0;
    var n_triangles: usize = 0;
    var n_polygons: usize = 0;
    var n_groups: usize = 0;
    var n_objects: usize = 0;
    var n_ignored: usize = 0;
    var largest: usize = 0;
    var x_min: Float = INFINITY;
    var x_max: Float = -INFINITY;
    var y_min: Float = INFINITY;
    var y_max: Float = -INFINITY;
    var z_min: Float = INFINITY;
    var z_max: Float = -INFINITY;

    // Fill position 0 with dummy vertex
    try vs.append(allocator, point(0,0,0));
    try vt.append(allocator, point(0,0,0));
    try vn.append(allocator, vector(0,0,0));

    const obj = group(allocator);

    var bytes: usize = @sizeOf(Object) + @sizeOf(Group);

    while (true) {
        var line = r.takeDelimiterInclusive('\n') catch |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        };
        n_lines += 1;
        line = line[0..line.len-1];              // Trim '\n'
        if (line.len < 3 or line[0] == '#') {    // Ignore empty lines and comments 
            continue;
        }
        if (line[line.len-1] == '\r') {
            line = line[0..line.len-1];          // Trim '\r'
            if (line.len < 3) {
                continue;
            }
        }
        // Ok to inspect line[0] and line[1]
        switch (line[0]) {
            'v' => {                    // Vertex
                line = line[1..];
                switch (line[0]) {
                    ' ' => {            // v
                        _ = try parseCoords(&coords, line[1..], 3, n_lines);
                        try vs.append(allocator, point(coords[0], coords[1], coords[2]));
                        x_min = @min(x_min, coords[0]);
                        x_max = @max(x_max, coords[0]);
                        y_min = @min(y_min, coords[1]);
                        y_max = @max(y_max, coords[1]);
                        z_min = @min(z_min, coords[2]);
                        z_max = @max(z_max, coords[2]);
                    },
                    'n' => {
                        _ = try parseCoords(&coords, line[1..], 3, n_lines);
                        try vn.append(allocator, vector(coords[0], coords[1], coords[2]));
                    },                  // vn
                    't' => {
                        _ = try parseCoords(&coords, line[1..], 1, n_lines);
                        try vt.append(allocator, point(coords[0], coords[1], coords[2]));
                    },                  // vt
                    else => {           // Ignore unknown v subcommands
                        n_ignored += 1;
                        continue;
                    },
                }
            },
            'f' => {                    // Face (polygon)
                line = line[1..];
                const MAXELEMS = 64;    // Max # of elements per f line
                var pnt: [MAXELEMS]usize = undefined;
                var txt: [MAXELEMS]usize = undefined;
                var nor: [MAXELEMS]usize = undefined;
                var tokens = std.mem.tokenizeScalar(u8, line[1..], ' ');
                // Parse 3 or more vertices
                var n: usize = 0;
                var have_normals = false;
                while (tokens.next()) |token| {
                    if (n == MAXELEMS) {
                        // std.debug.print("token={s}, line={s}\n", .{token,line});
                        return error.TooManyVertices;
                    }
                    // Eg: "-8/9/10"
                    const ov, const ot, const on = try parseFaceElement(token);
                    // Negative indices address the vertex array from the end: -1 = last index.
                    // Mathematically, all you have to do is add this negative value to the
                    // length of the array (vs.items.len) to get the correct index. However, in Zig
                    // all array indices must be of type usize, but you can't just add an isize to
                    // a usize because this would violate type safety. Therefore we have to resort
                    // to this trick of subtracting the absolute value of the negative index.
                    // This is ok because @abs(isize) returns a usize. 
                    if (ov) |x| {   // Vertex:  -8  (mandatory)
                        pnt[n] = if (x < 0) vs.items.len - @abs(x) else @abs(x);
                    }
                    if (ot) |x| {   //Texture:   9  (optional)
                        txt[n] = if (x < 0) vs.items.len - @abs(x) else @abs(x);
                    }
                    if (on) |x| {   // Normal:  10  (optional)
                        nor[n] = if (x < 0) vs.items.len - @abs(x) else @abs(x);
                        have_normals = true;
                    }
                    n += 1;
                }
                if (n < 3) return error.MissingVertices;
                if (n > 3) {
                    largest = @max(largest,n);
                    n_polygons += 1;
                }

                // Perform fan-triangulation of polygons.
                // Typically there's only 1 triangle (n == 3).
                // Sometimes there are 2 triangles making up a quadrilateral (n == 4).
                // But in some cases there can be dozens of points.
                // Use smoothTriangle when normals are available.
                if (have_normals) {
                    for (1..n-1) |i| {
                        var tri = smoothTriangle(allocator,
                                        vs.items[pnt[0]],
                                        vs.items[pnt[i]],
                                        vs.items[pnt[i+1]],
                                        vn.items[nor[0]],
                                        vn.items[nor[i]],
                                        vn.items[nor[i+1]]);
                        // tri.material.color = mth.mustardYellow;
                        // tri.material.transparency = 0.9;
                        // tri.material.refractive_index = 1.5;
                        tri.material = material.*;
                        obj.addShape(tri);
                        n_triangles += 1;
                        bytes += @sizeOf(Object) + @sizeOf(SmoothTriangle);
                    }
                } else {
                    for (1..n-1) |i| {
                        var tri = triangle(allocator,
                                        vs.items[pnt[0]],
                                        vs.items[pnt[i]],
                                        vs.items[pnt[i+1]]);
                        // tri.material.color = mth.mustardYellow;
                        // tri.material.transparency = 0.9;
                        // tri.material.refractive_index = 1.5;
                        tri.material = material.*;
                        obj.addShape(tri);
                        n_triangles += 1;
                        bytes += @sizeOf(Object) + @sizeOf(Triangle);
                    }
                }
            },
            'g' => {                    // Group
                n_groups += 1;          // For now, just count
            },
            'o' => {                    // Object
                n_objects += 1;         // For now, just count
            },
            else => {                   // Ignore unknown commands
                n_ignored += 1;
            }
        }
    }

    ostats.lines = n_lines;
    ostats.ignored = n_ignored;
    ostats.vertices = vs.items.len;
    ostats.vtextures = vt.items.len;
    ostats.vnormals = vn.items.len;
    ostats.triangles = n_triangles;
    ostats.polygons = n_polygons;
    ostats.largest = largest;
    ostats.groups = n_groups;
    ostats.objects = n_objects;
    ostats.bytes = bytes;
    ostats.x_min = x_min;
    ostats.x_max = x_max;
    ostats.y_min = y_min;
    ostats.y_max = y_max;
    ostats.z_min = z_min;
    ostats.z_max = z_max;

    vs.deinit(allocator);
    vt.deinit(allocator);
    vn.deinit(allocator);

    return obj;
}

/// Parse a line with at least `min` floating-point coordinates and store them
/// in the array `coords[]`. Eg: "0.123 0.234 0.345 1.0".
fn parseCoords(coord: []Float, line: []u8,  min: usize, line_num: usize) !usize {
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    var n: usize = 0;

    while (tokens.next()) |token| {
        if (n == coord.len) {
            printErr("Too many coordinates at line {d}: {s}\n", .{line_num, line});
            return error.TooManyCoordinates;
        }
        coord[n] = std.fmt.parseFloat(Float, token) catch |err| {
            printErr("\nError {} at line {d}: [{s}]\n[{s}]\n", .{err, line_num, token, line});
            return err;
        };
        n += 1;
    }
    if (n < min) {
        printErr("Missing coordinates at line {d}: {s}\n", .{line_num, line});
        return error.MissingCoordinates;
    }
    return n;
}

/// Parse one face element (e.g. "2" or "-2/3" or "2/3/4" or "2//4")
fn parseFaceElement(text: []const u8) !struct { ?isize, ?isize, ?isize } {
    var vs = [3]?isize{ null, null, null };
    var i: usize = 0;

    var iter = std.mem.splitScalar(u8, text, '/');

    while (iter.next()) |piece| {
        if (i == vs.len) return error.TooManyElements;
        if (piece.len > 0) {
            vs[i] = try std.fmt.parseInt(isize, piece, 10);
        }
        i += 1;
    }

    // At least the first index must be present
    if (i == 0) {
        return error.MissingVertices;
    }

    return .{ vs[0], vs[1], vs[2] };
}

fn showStats(os: *const ObjStats) void {
    printErr("     Read lines: {d}\n", .{os.lines});
    printErr("  Ignored lines: {d}\n", .{os.ignored});
    printErr("       Vertices: {d}\n", .{os.vertices});
    printErr("              X: [{d}, {d}]\n", .{os.x_min, os.x_max});
    printErr("              Y: [{d}, {d}]\n", .{os.y_min, os.y_max});
    printErr("              Z: [{d}, {d}]\n", .{os.z_min, os.z_max});
    printErr("Vertex textures: {d}\n", .{os.vtextures});
    printErr(" Vertex normals: {d}\n", .{os.vnormals});
    printErr("      Triangles: {d}\n", .{os.triangles});
    printErr("       Polygons: {d} ({d})\n", .{os.polygons, os.largest});
    printErr("         Groups: {d}\n", .{os.groups});
    printErr("        Objects: {d}\n", .{os.objects});


    printErr("         Memory: ", .{});
    if (os.bytes < 1024) {
        printErr("{d} B\n", .{os.bytes});
    } else if (os.bytes < 1024 * 1024) {
        printErr("{d} KB\n", .{@divTrunc(os.bytes, 1024)});
    } else {
        printErr("{d} MB\n", .{@divTrunc(os.bytes, 1024 * 1024)});
    }
    
    printErr("   Elapsed time: ", .{});
    if (os.elapsed < 1000) {
        printErr("{d} ms\n", .{os.elapsed}); 
    } else {
        printErr("{d} s\n", .{@divTrunc(os.elapsed, 1000)}); 
    }
}

const expect = std.testing.expect;

test "parseFaceElement" {
    var ve: ?isize = null;
    var vt: ?isize = null;
    var vn: ?isize = null;

    ve, vt, vn = try parseFaceElement("123");
    try expect(ve.? == 123);
    try expect(vt == null);
    try expect(vn == null);

    ve, vt, vn = try parseFaceElement("2/3");
    try expect(ve.? == 2);
    try expect(vt.? == 3);
    try expect(vn == null);

    ve, vt, vn = try parseFaceElement("-2/-3");
    try expect(ve.? == -2);
    try expect(vt.? == -3);
    try expect(vn == null);

    ve, vt, vn = try parseFaceElement("2/3/4");
    try expect(ve.? == 2);
    try expect(vt.? == 3);
    try expect(vn.? == 4);

    ve, vt, vn = try parseFaceElement("2//-4");
    try expect(ve.? == 2);
    try expect(vt == null);
    try expect(vn.? == -4);
}
