const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const mth = @import("math.zig");
const Float = mth.Float;
const Matrix = mth.Matrix;
const point = mth.point;
const vector = mth.vector;
const matMul = mth.matMul;

const mtl = @import("material.zig");
const Color = mtl.Color;
const Material = mtl.Material;
const white = mtl.white;
const red = mtl.red;
const blue = mtl.blue;
const green = mtl.green;
const black = mtl.black;
const yellow = mtl.yellow;
const gold = mtl.gold;
const mustardYellow = mtl.mustardYellow;
const lemonYellow = mtl.lemonYellow;
const pastelYellow = mtl.pastelYellow;
const glassMaterial = mtl.glassMaterial;
const testMaterial = mtl.testMaterial;

const obi = @import("object.zig");
const Object = obi.Object;
const cone = obi.cone;
const csg = obi.csg;
const cube = obi.cube;
const cylinder = obi.cylinder;
const glassSphere = obi.glassSphere;
const group = obi.group;
const plane = obi.plane;
const smoothTriangle = obi.smoothTriangle;
const sphere = obi.sphere;
const triangle = obi.triangle;

const obf = @import("objfile.zig");
const readObjFile = obf.readObjFile;

const pat = @import("pattern.zig");
const Pattern = pat.Pattern;
const stripes = pat.stripes;
const checkers = pat.checkers;
const rings = pat.rings;
const gradient = pat.gradient;

const rnd = @import("render.zig");
const Camera = rnd.Camera;
const PointLight = rnd.PointLight;
const Tracer = rnd.Tracer;
const World = rnd.World;

const sio = @import("stdio.zig");
const printErr = sio.printErr;

const trf = @import("transform.zig");
const invScaling = trf.invScaling;
const invTranslation = trf.invTranslation;
const invRotationX = trf.invRotationX;
const invRotationY = trf.invRotationY;
const invRotationZ = trf.invRotationZ;

pub const DemoOptions = struct {
    name: ?[]const u8 = null,
    width: usize = 300,
    height: usize = 300,
    threads: usize = 4,
};

pub fn renderDemo(io: Io, allocator: Allocator,  options: *DemoOptions) !void {
    const name = options.name.?;
    if (std.mem.eql(u8, name, "csg")) {
        try makeCSG(io, allocator, options);
    } else if (std.mem.eql(u8, name, "spheres")) {
        try makeGridOfSpheres(io, allocator, options);
    } else {
        printErr("Unknown demo name: {s}\n", .{name});
    }
}

fn makeGridOfSpheres(io: Io, allocator: Allocator, options: *DemoOptions) !void {
    const tracer = Tracer{};

    var world = World.init(PointLight{ .position = point(-15, 40, -70), .intensity = Color{1, 1, 1}}, allocator);

    const cam = Camera.init(options.width, options.height, std.math.pi / 4.0, point(-15, 33, -40), point(15,15,15), vector(0, 1, 0));

    var back = plane(allocator);
    back.material = Material{ .ambient = 1, .diffuse = 0, .specular = 0 };
    mth.matMulLeft(&back.itrans, &invRotationX(std.math.pi / 2.0));
    mth.matMulLeft(&back.itrans, &invTranslation(0, 0, 500));

    world.scene.addShape(back);

    var grp = group(allocator);

    const numZ = 10.0;
    const numY = 10.0;
    const numX = 10.0;
    var z: Float = 0;
    while (z < numZ) : (z += 1) {
        var y: Float = 0;
        while (y < numY) : (y += 1) {
            var x: Float = 0;
            while (x < numX) : (x += 1) {
                var sph = sphere(allocator);
                sph.material.color = Color{x/numX, y/numY, z/numZ};
                sph.itrans = invTranslation(x*3, y*3, z*3);
                grp.addShape(sph);
            }
        }
    }

    world.scene.addShape(grp);

    try world.renderThreads(&cam, "spheres.ppm", io, &tracer);

    world.deinit(); // Should free everything
}

fn makeCSG(io: Io, allocator: Allocator, options: *DemoOptions) !void {
    var floor = plane(allocator);
    const gray0 = Color{0.3, 0.3, 0.3};
    const gray1 = Color{0.6, 0.6, 0.6};
    floor.material.pattern = checkers(gray0, gray1);
    floor.material.specular = 0;

    var ball1 = sphere(allocator);
    ball1.chainTransf(&invScaling(1.3, 1.3, 1.3));
    ball1.chainTransf(&invTranslation(0, 1, 0));
    ball1.material = Material{};
    ball1.material.color = Color{1, 0.8, 0.1};
    ball1.material.diffuse = 0.7;
    ball1.material.specular = 0.3;
    ball1.material.reflective = 0;

    const ball2 = ball1.clone(allocator);
    const ball3 = ball1.clone(allocator);

    var green_material = Material{};
    green_material.color = Color{0.5, 0.9, 0.5};
    green_material.diffuse = 0.7;
    green_material.specular = 0.3;
    green_material.reflective = 0;

    var box1 = cube(allocator);
    box1.itrans = invTranslation(0, 1, 0);
    box1.material = green_material;

    const box2 = box1.clone(allocator);
    const box3 = box1.clone(allocator);

    const tracer = Tracer{};

    var world = World.init(PointLight{ .position = point(-2, 10, -10), .intensity = Color{1, 1, 1}}, allocator);

    const cam = Camera.init(options.width, options.height, 0.6, point(0, 8, -20), point(0,0,0), vector(0, 1, 0));

    const csg1 = csg(allocator, obi.CsgOp.csg_diff, box1, ball1 );
    csg1.chainTransf(&invRotationY(std.math.pi / 3.0));

    const csg2 = csg(allocator, obi.CsgOp.csg_inter, box2, ball2 );
    csg2.chainTransf(&invRotationY(std.math.pi / 3.0));
    csg2.chainTransf(&invTranslation(-4, 0, 0));

    const csg3 = csg(allocator, obi.CsgOp.csg_union, box3, ball3 );
    csg3.chainTransf(&invRotationY(std.math.pi / 3.0));
    csg3.chainTransf(&invTranslation(4, 0, 0));

    const csg1dup = csg1.clone(allocator);
    csg1dup.chainTransf(&invTranslation(0, 0, 4));

    const csg2dup = csg2.clone(allocator);
    csg2dup.chainTransf(&invTranslation(0, 0, 4));

    const csg3dup = csg3.clone(allocator);
    csg3dup.chainTransf(&invTranslation(0, 0, 4));

    var cyl11 = cylinder(allocator, -3, 3, true);
    cyl11.chainTransf(&invScaling(0.5, 0.5, 0.5));
    cyl11.material.color = gold;

    var cyl12 = cylinder(allocator, -3, 3, true);
    cyl12.chainTransf(&invScaling(0.5, 0.5, 0.5));
    cyl12.chainTransf(&invRotationZ(std.math.pi / 2.0));
    cyl12.material.color = gold;

    var cyl13 = cylinder(allocator, -3, 3, true);
    cyl13.chainTransf(&invScaling(0.5, 0.5, 0.5));
    cyl13.chainTransf(&invRotationX(std.math.pi / 2.0));
    cyl13.material.color = gold;

    var grp4 = group(allocator);
    grp4.addShape(cyl11);
    grp4.addShape(cyl12);
    grp4.addShape(cyl13);

    // Center
    var box4 = cube(allocator);
    box4.material = green_material;
    var csg4 = csg(allocator, obi.CsgOp.csg_diff, box4, grp4);
    csg4.chainTransf(&invRotationY(std.math.pi / 3.0));
    csg4.chainTransf(&invTranslation(0, 1, -4));

    // Left
    const grp5 = grp4.clone(allocator);
    const box5 = box4.clone(allocator);
    var csg5 = csg(allocator, obi.CsgOp.csg_inter, box5, grp5);
    csg5.chainTransf(&invRotationY(-std.math.pi / 3.0));
    csg5.chainTransf(&invTranslation(-4, 1, -4));

    // Right
    const grp6 = grp4.clone(allocator);
    const box6 = box4.clone(allocator);
    var csg6 = csg(allocator, obi.CsgOp.csg_union, box6, grp6);
    csg6.chainTransf(&invRotationY(std.math.pi / 3.0));
    csg6.chainTransf(&invTranslation(4, 1, -4));


    world.scene.addShape(floor);
    world.scene.addShape(csg1);
    world.scene.addShape(csg2);
    world.scene.addShape(csg3);
    world.scene.addShape(csg1dup);
    world.scene.addShape(csg2dup);
    world.scene.addShape(csg3dup);

    world.scene.addShape(csg4);
    world.scene.addShape(csg5);
    world.scene.addShape(csg6);

    try world.renderThreads(&cam, "csg.ppm", io, &tracer);

    world.deinit(); // Should free everything
}
