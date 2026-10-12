const std = @import("std");

const obi = @import("object.zig");
const Group = obi.Group;

const obf = @import("objfile.zig");
const ObjStats = obf.ObjStats;
const readObjFile = obf.readObjFile;

const mth = @import("math.zig");
const mtl = @import("material.zig");
const Material = mtl.Material;

const pat = @import("pattern.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // const allocator = init.gpa;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const material = Material{};
    var os: ObjStats = undefined;

    std.debug.print("Sizeof(Float)    = {d}\n", .{@sizeOf(mth.Float)});
    std.debug.print("Sizeof(Object)   = {d}\n", .{@sizeOf(obi.Object)});
    std.debug.print("Sizeof(Material) = {d}\n", .{@sizeOf(mtl.Material)});
    std.debug.print("Sizeof(Matrix)   = {d}\n", .{@sizeOf(mth.Matrix)});
    std.debug.print("Sizeof(Pattern)  = {d}\n", .{@sizeOf(pat.Pattern)});

    for (args[1..]) |arg| {
        std.debug.print("\nReading {s}\n", .{arg});

        _ = try readObjFile(io, allocator, arg, &material, &os);
        // defer group.deinit(allocator);

        std.debug.print("     Read lines: {d}\n", .{os.lines});
        std.debug.print("  Ignored lines: {d}\n", .{os.ignored});
        std.debug.print("       Vertices: {d}\n", .{os.vertices});
        std.debug.print("              X: [{d}, {d}]\n", .{os.x_min, os.x_max});
        std.debug.print("              Y: [{d}, {d}]\n", .{os.y_min, os.y_max});
        std.debug.print("              Z: [{d}, {d}]\n", .{os.z_min, os.z_max});
        std.debug.print("Vertex textures: {d}\n", .{os.vtextures});
        std.debug.print(" Vertex normals: {d}\n", .{os.vnormals});
        std.debug.print("      Triangles: {d}\n", .{os.triangles});
        std.debug.print("       Polygons: {d} ({d})\n", .{os.polygons, os.largest});
        std.debug.print("         Groups: {d}\n", .{os.groups});
        std.debug.print("        Objects: {d}\n", .{os.objects});


        std.debug.print("         Memory: ", .{});
        if (os.bytes < 1024) {
            std.debug.print("{d} B\n", .{os.bytes});
        } else if (os.bytes < 1024 * 1024) {
            std.debug.print("{d} KB\n", .{@divTrunc(os.bytes, 1024)});
        } else {
            std.debug.print("{d} MB\n", .{@divTrunc(os.bytes, 1024 * 1024)});
        }
        
        std.debug.print("   Elapsed time: ", .{});
        if (os.elapsed < 1000) {
            std.debug.print("{d} ms\n", .{os.elapsed}); 
        } else {
            std.debug.print("{d} s\n", .{@divTrunc(os.elapsed, 1000)}); 
        }
    }
}
