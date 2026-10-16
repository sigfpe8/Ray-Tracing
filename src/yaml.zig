//! This is not a generic YAML parser! 
//! It is a very simplified function streamlined to read scene descriptions.
//! In most cases we assume the syntax is correct and perform only limited
//! error checking.

const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Reader = Io.Reader;
const Writer = Io.Writer;
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const startsWith = std.mem.startsWith;

const mth = @import("math.zig");
const Float = mth.Float;
const Vector = mth.Vector;
const Matrix = mth.Matrix;
const Point = mth.Point;
const matIdentity = mth.matIdentity;
const vector = mth.vector;
const point = mth.point;

const mtl = @import("material.zig");
const Color = mtl.Color;
const Material = mtl.Material;
const black = mtl.black;
const white = mtl.white;
const testMaterial = mtl.testMaterial;

const obi = @import("object.zig");
const Object = obi.Object;
const ObjType = obi.ObjType;
const cone = obi.cone;
const cube = obi.cube;
const cylinder = obi.cylinder;
const group = obi.group;
const plane = obi.plane;
const sphere = obi.sphere;

const obf = @import("objfile.zig");
const readObjFile = obf.readObjFile;

const pat = @import("pattern.zig");
const Pattern = pat.Pattern;
const PatternType = pat.PatternType;
const stripes = pat.stripes;
const checkers = pat.checkers;
const rings = pat.rings;
const gradient = pat.gradient;

const rnd = @import("render.zig");
const Camera = rnd.Camera;
const PointLight = rnd.PointLight;
const Setting = rnd.Setting;
const World = rnd.World;

const sio = @import("stdio.zig");
const printErr = sio.printErr;

const trf = @import("transform.zig");

const LevelLine = struct {
    lineno: usize,      // Line number
    level: usize,       // # of leading blanks
    line: []const u8,   // Begins with first non-blank character
};

var lineno: usize = 0;  // Current line (for error reporting)

const YamlError = error{
    InvalidTag,
};

var symTable: std.StringHashMap([]const LevelLine) = undefined;

pub fn renderYaml(io: Io, allocator: Allocator, inp_file: []const u8) !void {
    const ext = std.fs.path.extension(inp_file);
    if (!std.ascii.eqlIgnoreCase(ext, ".yml") and !std.ascii.eqlIgnoreCase(ext, ".yaml")) {
        printErr("Scene description file {s} must have '.yml' or '.yaml' extension (not {s})\n", .{inp_file, ext});
        return error.InvalidFileName;
    }

    const basename = inp_file[0..inp_file.len - ext.len];
    const out_file = try std.fmt.allocPrint(allocator, "{s}{s}", .{ basename, ".ppm" });
    defer allocator.free(out_file);

    const setting = try readYamlFile(io, allocator, inp_file);

    const world = setting.world;
    try world.renderThreads(&setting.camera, out_file, io, 4);
}

fn readYamlFile(io: Io, allocator: Allocator, fname: []const u8) !Setting {
    const file = Io.Dir.cwd().openFile(io, fname, .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) {
            printErr("Could not open '{s}'\n", .{fname});
        }
        return err;
    };
    defer file.close(io);

    // Where we store "define: <name>" blocks
    symTable = std.StringHashMap([]const LevelLine).init(allocator);
    defer symTable.deinit();

    // YAML files are typically small
    // Allocate a buffer big enough to hold the whole file
    const file_size = try file.length(io);
    const raw_buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(raw_buffer);

    // Read the whole thing
    _ = try file.readPositionalAll(io, raw_buffer, 0);

    // Dynamic array to hold the lines and level info
    var lines: std.ArrayList(LevelLine) = .empty;
    defer lines.deinit(allocator);

    // var iter = std.mem.tokenizeAny(u8, raw_buffer, "\r\n");
    // The above tokenization would skip empty lines and this would
    // result in incorrect line numbers. Since correct line numbers
    // are essential to good error reporting, we changed to the method
    // below, which creates a stream from the raw buffer. Note that
    // by keeping the whole file in the raw buffer, the slices that
    // are put in the LineLevel array are valid until the exit of this
    // function. Had we opted for a stream directly from the file, this
    // would require allocating new storage for each line.

    var reader: Reader = .fixed(raw_buffer);
    var r: *Reader = &reader;
    var lnum: usize = 0;

    while (true) {
        var line = r.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        lnum += 1;
        line = line[0..line.len-1];              // Trim '\n'
        if (line.len > 0 and line[line.len-1] == '\r') {
            line = line[0..line.len-1];          // Trim '\r'
        }
        if (line.len == 0) {                     // Ignore empty lines
            continue;
        }
        var i: usize = 0;   // Count indentation blanks (level)
        while (i < line.len) : (i += 1) {
            if (line[i] != ' ') break;
        }
        if (i < line.len and line[i] == '#') {   // Ignore comment lines
            continue;
        }
        try lines.append(allocator, .{ .lineno = lnum,
                                                 .level = i,
                                                 .line = std.mem.trimEnd(u8, line[i..], " ") });
    }
   
    // for (lines.items) |ll| {
    //     std.debug.print("{d:2>}  [{d}] '{s}\n", .{ll.lineno, ll.level, ll.line});
    // }

    const setting = try readYaml(io, allocator, lines.items);

    return setting;
}

fn readYaml(io: Io, allocator: Allocator, lines: []const LevelLine) !Setting {
    var cam: Camera = undefined;
    var light = PointLight{ .position = point(0, 10, -10), .intensity = Color{1, 1, 1}};
    var world = World.init(light, allocator);

    var ind: usize = 0;     // Index into lines[]
    var inc: usize = 1;     // Index increment from lower levels

    while (ind < lines.len) : (ind += inc) {
        const line = lines[ind].line;
        lineno = lines[ind].lineno;
        inc = 1;

        if (eql(u8, line, "- add: camera")) {
            cam = try readCamera(lines[ind..], &inc);
        } else if (startsWith(u8, line, "- add: cube")) {
            const obj = try readObject(allocator, lines[ind..], &inc, .objCube);
            world.scene.addShape(obj);
            // std.debug.print("Added a cube, mat={}\n", .{obj.material});
        } else if (startsWith(u8, line, "- add: group")) {
            const obj = try readGroup(io, allocator, lines[ind..], &inc);
            world.scene.addShape(obj);
            // std.debug.print("Added a group\n", .{});
        } else if (eql(u8, line, "- add: light") or eql(u8, line, "- add: point-light")) {
            light = try readLight(lines[ind..], &inc);
            world.light = light;
        } else if (eql(u8, line, "- add: plane")) {
            const obj = try readObject(allocator, lines[ind..], &inc, .objPlane);
            world.scene.addShape(obj);
            // std.debug.print("Added a plane\n", .{});
        } else if (eql(u8, line, "- add: sphere")) {
            const obj = try readObject(allocator, lines[ind..], &inc, .objSphere);
            world.scene.addShape(obj);
            // std.debug.print("Added a sphere, mat={}\n", .{obj.material});
        } else if (startsWith(u8, line, "- define: ")) {
            try readDefine(lines[ind..], &inc);
        } else {
            return yamlError("Unknown YAML tag", line);
        }
    }

    world.addAxes();
    
    const setting = Setting{  .world = world, .camera = cam, };
    return setting;
}

fn readCamera(lines: []const LevelLine, pinc: *usize) !Camera {
    // Default parameters for the camera
    var hsize: usize = 100;
    var vsize: usize = 100;
    var fov: Float = std.math.pi / 4.0;
    var from = point(0, 1, -1);
    var to = point(0, 1, 1);
    var up = vector(0, 1, 0);
    var ind: usize = 1;     // Skip parent node at ind == 0
    const base_level = lines[0].level;

    while (ind < lines.len) : (ind += 1) {
        const line = lines[ind].line;
        const level = lines[ind].level;
        lineno = lines[ind].lineno;

        if (level <= base_level) {    // End of camera block?
            break;
        }

        if (startsWith(u8, line, "width: ")) {
            hsize = try std.fmt.parseUnsigned(usize, line[7..],10);
        } else if (startsWith(u8, line, "height: ")) {
            vsize = try std.fmt.parseUnsigned(usize, line[8..],10);
        } else if (startsWith(u8, line, "field-of-view: ")) {
            _ = try parseFloat(line[15..], &fov);
        } else if (startsWith(u8, line, "from: ")) {
            from = try parsePoint(line[6..]);
        } else if (startsWith(u8, line, "to: ")) {
            to = try parsePoint(line[4..]);
        } else if (startsWith(u8, line, "up: ")) {
            up = try parseVector(line[4..]);
        } else {
            return yamlError("Invalid camera parameter", line);
        }
    }

    pinc.* = ind;    // # of lines consumed at this level including base line
    const cam = Camera.init(hsize, vsize, fov, from, to, up);
    return cam;
}

fn readDefine(lines: []const LevelLine, pinc: *usize) !void {
    var ind: usize = 1;     // Skip parent node at ind == 0
    const base_level = lines[0].level;

    //- define: <name>
    const name = lines[0].line[10..];
    const beg = ind;

    while (ind < lines.len) : (ind += 1) {
        const level = lines[ind].level;

        if (level <= base_level) {    // End of define block?
            break;
        }
    }

    try symTable.put(name, lines[beg..ind]);
    pinc.* = ind;    // # of lines consumed at this level including base line
}

fn readGroup(io: Io, allocator: Allocator, lines: []const LevelLine, pinc: *usize) !*Object {
    // E.g. - add: group
    //        obj: astronaut.obj
    //        transform:
    //          - [rotate-x, -PI/4]
    //          - [rotate-y, PI/6]
    var material = Material{};
    var itrans: Matrix = matIdentity();
    var inc: usize = 1;     // Index increment from lower levels
    var ind: usize = 1;     // Skip parent node at ind == 0
    const base_level = lines[0].level;
    var grp: *Object = undefined;
    var fname: ?[]const u8 = null;

    while (ind < lines.len) : (ind += inc) {
        inc = 1;
        const line = lines[ind].line;
        const level = lines[ind].level;
        lineno = lines[ind].lineno;

        if (level <= base_level) {    // End of plane block?
            break;
        }

        if (startsWith(u8, line, "obj:")) {
            fname = std.mem.trim(u8, line[4..], " ");
        } else if (startsWith(u8, line, "material:")) {
            try readMaterial(lines[ind..], &inc, &material);
        } else if (startsWith(u8, line, "transform:")) {
            try readTransform(lines[ind..], &inc, &itrans);
        } else {
            return yamlError("Invalid object parameter", line);
        }
    }

    pinc.* = ind;    // # of lines consumed at this level including base line

    if (fname) |name| {
        grp = try readObjFile(io, allocator, name, &material, null);
    } else {
        grp = group(allocator);
    }

    grp.itrans = itrans;

    return grp;
}

fn readLight(lines: []const LevelLine, pinc: *usize) !PointLight {
    // Default parameters for the light
    var intensity: Color = Color{0.5, 0.5, 0.5};
    var position: Point = point(-10, 10, -10);
    var ind: usize = 1;     // Skip parent node at ind == 0
    const base_level = lines[0].level;

    while (ind < lines.len) : (ind += 1) {
        const line = lines[ind].line;
        const level = lines[ind].level;
        lineno = lines[ind].lineno;

        if (level <= base_level) {    // End of light block?
            break;
        }

        if (startsWith(u8, line, "at: ")) {
            position = try parsePoint(line[4..]);
        } else if (startsWith(u8, line, "intensity: ")) {
            intensity = try parseColor(line[11..]);
        } else {
            return yamlError("Invalid light parameter", line);
        }
    }

    pinc.* = ind;    // # of lines consumed at this level including base line
    return PointLight{ .intensity = intensity, .position = position };
}

fn readMaterial(lines: []const LevelLine, pinc: *usize, material: *Material) !void {
    var inc: usize = 1;     // Index increment from lower levels
    var ind: usize = 1;     // Skip parent node at ind == 0
    const base_level = lines[0].level;

    // material: <name> ?
    // The first line can also be "value:" or "extend:" when called recursively
    if (startsWith(u8, lines[0].line, "material:")) {
        const name = std.mem.trim(u8, lines[0].line[9..], " ");
        if (name.len > 0) {
            var rinc: usize = 1;
            const rlines = try symLookUp(name);
            try readMaterial(rlines, &rinc, material);
            return;
        }
    }

    if (startsWith(u8, lines[0].line, "extend:")) {
        const name = std.mem.trim(u8, lines[0].line[7..], " ");
        if (name.len > 0) {
            var rinc: usize = 1;
            const rlines = try symLookUp(name);
            try readMaterial(rlines, &rinc, material);
            if (startsWith(u8, lines[1].line, "value:")) {
                ind += 1;   // Skip value: tag
            }
        }
        // Continue below with parameters that extend this base material
    }
        
    while (ind < lines.len) : (ind += inc) {
        inc = 1;
        const line = lines[ind].line;
        const level = lines[ind].level;
        lineno = lines[ind].lineno;

        if (level <= base_level) {    // End of material block?
            break;
        }

        if (startsWith(u8, line, "color: ")) {
            material.color = try parseColor(line[7..]);
        } else if (startsWith(u8, line, "ambient: ")) {
            material.ambient = try std.fmt.parseFloat(Float, line[9..]);
        } else if (startsWith(u8, line, "diffuse: ")) {
            material.diffuse = try std.fmt.parseFloat(Float, line[9..]);
        } else if (startsWith(u8, line, "specular: ")) {
            material.specular = try std.fmt.parseFloat(Float, line[10..]);
        } else if (startsWith(u8, line, "shininess: ")) {
            material.shininess = try std.fmt.parseFloat(Float, line[11..]);
        } else if (startsWith(u8, line, "reflective: ")) {
            material.reflective = try std.fmt.parseFloat(Float, line[12..]);
        } else if (startsWith(u8, line, "transparency: ")) {
            material.transparency = try std.fmt.parseFloat(Float, line[14..]);
        } else if (startsWith(u8, line, "refractive-index: ")) {
            material.refractive_index = try std.fmt.parseFloat(Float, line[18..]);
        } else if (startsWith(u8, line, "pattern:")) {
            material.pattern = try readPattern(lines[ind..], &inc);
        } else {
            return yamlError("Invalid material parameter", line);
        }
    }

    pinc.* = ind;    // # of lines consumed at this level including base line
}

fn readObject(allocator: Allocator, lines: []const LevelLine, pinc: *usize, obj_type: ObjType) !*Object {
    var material = Material{};
    var itrans: Matrix = matIdentity();
    // var inc: usize = 1;     // Index increment from lower levels
    // var ind: usize = 1;     // Skip parent node at ind == 0
    // const base_level = lines[0].level;

    // while (ind < lines.len) : (ind += inc) {
    //     inc = 1;
    //     const line = lines[ind].line;
    //     const level = lines[ind].level;

    //     if (level <= base_level) {    // End of plane block?
    //         break;
    //     }

    //     if (startsWith(u8, line, "material:")) {
    //         try readMaterial(lines[ind..], &inc, &material);
    //     } else if (startsWith(u8, line, "transform:")) {
    //         try readTransform(lines[ind..], &inc, &itrans);
    //     } else {
    //         printErr("Invalid object parameter: {s}\n", .{line});
    //         return error.InvalidTag;
    //     }
    // }

    // pinc.* = ind;    // # of lines consumed at this level including base line

    try readObjRec(lines, pinc, &material, &itrans);

    const obj: *Object = switch(obj_type) {
        .objCone => cone(allocator, -1, 0, true),
        .objCube => cube(allocator),
        .objCylinder => cylinder(allocator, 0, 1, true),
        .objPlane => plane(allocator),
        .objSphere => sphere(allocator),
    };
    obj.material = material;
    obj.itrans = itrans;

    return obj;
}

fn readObjRec(lines: []const LevelLine, pinc: *usize, material: *Material, itrans: *Matrix) anyerror!void {
    var inc: usize = 1;     // Index increment from lower levels
    var ind: usize = 1;     // Skip parent node at ind == 0
    var base_level = lines[0].level;

    if (!startsWith(u8, lines[0].line, "- add:")) {
        // When called recusively (i.e. not from "add: <obj>"), start with ind = 0
        // which should be "material:", "transform:" or another "extend:"
        ind = 0;
        base_level = 0;
    }

    while (ind < lines.len) : (ind += inc) {
        inc = 1;
        const line = lines[ind].line;
        const level = lines[ind].level;
        lineno = lines[ind].lineno;

        if (level <= base_level) {    // End of plane block?
            break;
        }

        if (startsWith(u8, line, "extend:")) {
            try readExtendObj(line, material, itrans);
        } else if (startsWith(u8, line, "material:")) {
            try readMaterial(lines[ind..], &inc, material);
        } else if (startsWith(u8, line, "transform:")) {
            try readTransform(lines[ind..], &inc, itrans);
        } else {
            return yamlError("nvalid object parameter", line);
        }
    }

    pinc.* = ind;    // # of lines consumed at this level including base line
}

fn readExtendObj(line: []const u8, material: *Material, itrans: *Matrix) !void {
    // Eg: extend: [ red-material, large-object ]
    if (line[8] != '[' and line[line.len-1] != ']') {
        return error.InvalidObjectExtend;
    }
    var iter = std.mem.tokenizeAny(u8, line[9..line.len-1], ",");

    while (iter.next()) |sym| {
        const name = std.mem.trim(u8, sym, " ");
        if (name.len == 0) continue;
        var rinc: usize = 1;
        const rlines = try symLookUp(name);
        // std.debug.print("name={s}\n", .{name});
        // for (rlines) |rl| {
        //     std.debug.print("   {d} - [{d}] - {s}\n", .{rl.lineno, rl.level, rl.line});
        // }

        try readObjRec(rlines, &rinc, material, itrans);
    }

}

fn readPattern(lines: []const LevelLine, pinc: *usize) !Pattern {
    // Default parameters for the pattern
    var colorA: Color = black;
    var colorB: Color = white;
    var patType: PatternType = .patNone;
    var itrans: Matrix = matIdentity();
    var inc: usize = 1;     // Index increment from lower levels
    var ind: usize = 1;     // Skip parent node at ind == 0
    const base_level = lines[0].level;

    while (ind < lines.len) : (ind += inc) {
        inc = 1;
        const line = lines[ind].line;
        const level = lines[ind].level;
        lineno = lines[ind].lineno;

        if (level <= base_level) {    // End of pattern block?
            break;
        }

        if (startsWith(u8, line, "type: ")) {
            patType = parsePatternType(line[6..]);
        } else if (startsWith(u8, line, "colors:")) {
            colorA, colorB = try readPatternColors(lines[ind..], &inc);
        } else if (startsWith(u8, line, "transform:")) {
            try readTransform(lines[ind..], &inc, &itrans);
        } else {
            return yamlError("nvalid pattern parameter", line);
        }
    }

    pinc.* = ind;    // # of lines consumed at this level including base line
    var pattern: Pattern = switch (patType) {
        .patCheckers => checkers(colorA, colorB),
        .patGradient => gradient(colorA, colorB),
        .patRings    => rings(colorA, colorB),
        .patStripes  => stripes(colorA, colorB),
        .patNone     => { return error.InvalidPattern; },
    };
    pattern.itrans = itrans;
    return pattern;
}

fn readPatternColors(lines: []const LevelLine, pinc: *usize) !struct { Color, Color } {
    // Default colors
    var colorA: Color = black;
    var colorB: Color = white;
    var ind: usize = 1;     // Skip parent node at ind == 0
    const base_level = lines[0].level;

    while (ind < lines.len and ind < 3) : (ind += 1) {
        const line = lines[ind].line;
        const level = lines[ind].level;
        lineno = lines[ind].lineno;

        if (level <= base_level) {    // End of pattern block?
            break;
        }

        if (startsWith(u8, line, "- [")) {
            if (ind == 1) {
                colorA = try parseColor(line[1..]);
            } else {
                colorB = try parseColor(line[1..]);
            }
        }
    }

    pinc.* = ind;    // # of lines consumed at this level including base line
    return .{ colorA, colorB };
}

fn readTransform(lines: []const LevelLine, pinc: *usize, itrans: *Matrix) !void {
    var ind: usize = 1;     // Skip parent node at ind == 0
    const base_level = lines[0].level;

    while (ind < lines.len) : (ind += 1) {
        var line = lines[ind].line;
        const level = lines[ind].level;
        lineno = lines[ind].lineno;

        if (level <= base_level) {    // End of transform block?
            break;
        }

        var mat: Matrix = undefined;
        var angle: Float = undefined;
        var x: Float = undefined;
        var y: Float = undefined;
        var z: Float = undefined;
        // FIX: skip blanks and don't assume fixed spacing
        if (startsWith(u8, line, "- [")) {
            line = std.mem.trim(u8, line[3..], " ");
            if (startsWith(u8, line, "rotate-x,")) {
                var rest = try parseFloat(line[9..], &angle);
                // std.debug.print("RotateX={d}\n", .{angle});
                rest = try skipChar(rest, ']');
                mat = trf.invRotationX(angle);
            } else if (startsWith(u8, line, "rotate-y,")) {
                var rest = try parseFloat(line[9..], &angle);
                // std.debug.print("RotateY={d}\n", .{angle});
                rest = try skipChar(rest, ']');
                mat = trf.invRotationY(angle);
            } else if (startsWith(u8, line, "rotate-z,")) {
                var rest = try parseFloat(line[9..], &angle);
                // std.debug.print("RotateZ={d}\n", .{angle});
                rest = try skipChar(rest, ']');
                mat = trf.invRotationZ(angle);
            } else if (startsWith(u8, line, "scale,")) {
                var rest = try parseTriple(line[6..], &x, &y, &z);
                // std.debug.print("Scale=({d}, {d}, {d})\n", .{x,y,z});
                rest = try skipChar(rest, ']');
                mat = trf.invScaling(x,y,z);
            } else if (startsWith(u8, line, "translate,")) {
                var rest = try parseTriple(line[10..], &x, &y, &z);
                // std.debug.print("Translate=({d}, {d}, {d})\n", .{x,y,z});
                rest = try skipChar(rest, ']');
                mat = trf.invTranslation(x,y,z);
            } else {
                return yamlError("Invalid transform parameter", line);
            }
        } else if (startsWith(u8, line, "- ")) {
            var rinc: usize = 1;
            const name = std.mem.trim(u8, line[2..], " ");
            const rlines = try symLookUp(name);
            try readTransform(rlines, &rinc, itrans);
            continue;
        } else {
            return yamlError("Invalid transform parameter", line);
        }

        // Update itrans by multiplying it by the above transform
        mth.matMulLeft(itrans, &mat);
    }

    pinc.* = ind;    // # of lines consumed at this level including base line
}

fn parsePatternType(line: []const u8) PatternType {
    if (eql(u8, line, "checkers")) {
        return .patCheckers;
    }

    if (eql(u8, line, "gradient")) {
        return .patGradient;
    }

    if (eql(u8, line, "rings")) {
        return .patRings;
    }

    if (eql(u8, line, "stripes")) {
        return .patStripes;
    }

    return .patNone;
}

fn parsePoint(buf: []const u8) !Point {
    // [ -4.5, 0.85, -4 ]
    var x: Float = undefined;
    var y: Float = undefined;
    var z: Float = undefined;

    var line = try skipChar(buf, '[');
    line = try parseTriple(line, &x, &y, &z);
    line = try skipChar(line, ']');

    return point(x, y, z);
}

fn parseVector(buf: []const u8) !Vector {
    // [ -4.5, 0.85, -4 ]
    var x: Float = undefined;
    var y: Float = undefined;
    var z: Float = undefined;

    var line = try skipChar(buf, '[');
    line = try parseTriple(line, &x, &y, &z);
    line = try skipChar(line, ']');

    return vector(x, y, z);
}

fn parseColor(buf: []const u8) !Color {
    // [ 1, 0.85, 0.25 ]
    var r: Float = undefined;
    var g: Float = undefined;
    var b: Float = undefined;

    var line = try skipChar(buf, '[');
    line = try parseTriple(line, &r, &g, &b);
    line = try skipChar(line, ']');

    return Color{ r, g, b };
}

fn parseTriple(buf: []const u8, x: *Float, y: *Float, z: *Float) ![]const u8 {
    var line = try parseFloat(buf, x);
    line = try skipChar(line, ',');
    line = try parseFloat(line, y);
    line = try skipChar(line, ',');
    line = try parseFloat(line, z);
    return line;
}

fn parseFloat(line: []const u8, p: *Float) ![]const u8 {
    const num = std.mem.trim(u8, line, " ");
    var i: usize = 0;
    var b: usize = 0;
    var sign: u8 = '+';
    // Check for PI/n or -PI/n
    if (num.len >= 4) {
        if (num[0] == '-') {
            b = 1;
            sign = '-';
        }
        if (std.ascii.eqlIgnoreCase(num[b..b+3], "pi/") and std.ascii.isDigit(num[b+3])) {
            i = b + 4;
            while (i < num.len) : (i += 1) {
                if (!std.ascii.isDigit(num[i])) {
                    break;
                }
            }
            const n = try std.fmt.parseFloat(Float, num[b+3..i]);
            p.* = if (sign == '+') std.math.pi / n else -std.math.pi / n;
            // std.debug.print("parseFloat({s} -> {d}, rest = {s})\n", .{num[0..i], p.*, num[i..] });
            return num[i..];
        }
    }
    // Literal floating-point number
    while (i < num.len) : (i += 1) {
        const c = num[i];
        // FIX: do proper Float parsing!
        if (c != '-' and c != '.' and !std.ascii.isDigit(c)) {
            break;
        }
    }
    // i is 1 char past the number
    p.* = try std.fmt.parseFloat(Float, num[0..i]);
    return num[i..];
}

fn skipChar(line: []const u8, chr: u8) ![]const u8 {
    var i: usize = 0;
    // Skip initial blanks
    while (i < line.len) : (i += 1) {
        if (line[i] != ' ') {
            break;
        }
    } else {    // Reached eol
        printErr("Error at line [{d}]: Expected '{c}'\n", .{lineno, chr});
        return error.EndOfString;
    }
    // Check for expected character
    if (line[i] != chr) {
        printErr("Error at line [{d}]: Expected '{c}'\n", .{lineno, chr});
        return error.InvalidCharacter;
    }
    return line[i+1..];
}

fn yamlError(msg: []const u8, line: []const u8) YamlError {
    printErr("Error at line [{d}]: {s}: '{s}'\n", .{lineno, msg, line});
    return YamlError.InvalidTag;
}

fn symTablePrint() void {
    var iter = symTable.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const lines = entry.value_ptr.*;
        std.debug.print("name={s}\n", .{name});
        for (lines) |line| {
            std.debug.print("  [{d}] {s}\n", .{ line.level, line.line });
        }
    }
}

fn symLookUp(name: []const u8) ![]const LevelLine {
    // std.debug.print("Looking up '{s}'\n", .{name});
    if (symTable.get(name)) |lines| {
        return lines;
    } else {
        printErr("Unknown symbol: [{d}] '{s}'\n", .{lineno, name});
        return error.SymbolNotFound;
    }
}
