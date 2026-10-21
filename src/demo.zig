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
    } else if (std.mem.eql(u8, name, "pawn")) {
        try makePawn(io, allocator, options);
    } else if (std.mem.eql(u8, name, "pumpkin")) {
        try makePumpkin(io, allocator, options);
    } else if (std.mem.eql(u8, name, "spheres")) {
        try makeGridOfSpheres(io, allocator, options);
    } else if (std.mem.eql(u8, name, "teapot")) {
        try makeTeapot(io, allocator, options);
    } else {
        printErr("Unknown demo name: {s}\n", .{name});
    }
}

fn makeGridOfSpheres(io: Io, allocator: Allocator, options: *DemoOptions) !void {
    _ = options;
    const tracer = Tracer{};

    var world = World.init(
        PointLight{ .position = point(-15, 40, -70), .intensity = Color{1, 1, 1}},
        allocator);

    const cam = Camera.init(1000, 1000, std.math.pi / 4.0,
                                point(-15, 33, -40), point(15,15,15), vector(0, 1, 0));

    var back = plane(allocator);
    back.material = Material{ .ambient = 1, .diffuse = 0, .specular = 0 };
    mth.matMulLeft(&back.itrans, &invRotationX(std.math.pi / 2.0));
    mth.matMulLeft(&back.itrans, &invTranslation(0, 0, 500));

    world.scene.addShape(back);

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
                world.scene.addShape(sph);
            }
        }
    }

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

    var box1 = cube(allocator);
    box1.itrans = invTranslation(0, 1, 0);
    box1.material = Material{};
    box1.material.color = Color{0.5, 0.9, 0.5};
    box1.material.diffuse = 0.7;
    box1.material.specular = 0.3;
    box1.material.reflective = 0;

    const box2 = box1.clone(allocator);
    const box3 = box1.clone(allocator);

    const tracer = Tracer{};

    var world = World.init(
        PointLight{ .position = point(-2, 10, -10), .intensity = Color{1, 1, 1}},
        allocator);

    // const grp = group(allocator);
    // grp.addShape(box);
    // grp.addShape(ball1);
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

    var cone1 = cone(allocator, -1, 0, false);
    cone1.chainTransf(&invTranslation(0,2,-3));
    cone1.material.color = gold;

    var cyl1 = cylinder(allocator, 0, 1, false);
    cyl1.chainTransf(&invTranslation(0, 0, -3));
    cyl1.material.color = green;

    var grp1 = group(allocator);
    grp1.addShape(cone1);
    grp1.addShape(cyl1);

    var grp2 = grp1.clone(allocator);
    grp2.chainTransf(&invRotationZ(std.math.pi / 2.0));
    grp2.chainTransf(&invTranslation(4, 0, 0));

    var grp3 = grp1.clone(allocator);
    grp3.chainTransf(&invRotationZ(-std.math.pi / 2.0));
    grp3.chainTransf(&invTranslation(-4, 0, 0));

    const cam = Camera.init(options.width, options.height, std.math.pi / 5.0,
                            point(0, 5, -8), point(0,0,0), vector(0, 1, 0));

    world.scene.addShape(floor);
    world.scene.addShape(csg1);
    world.scene.addShape(csg2);
    world.scene.addShape(csg3);
    world.scene.addShape(csg1dup);
    world.scene.addShape(csg2dup);
    world.scene.addShape(csg3dup);

    world.scene.addShape(grp1);
    world.scene.addShape(grp2);
    world.scene.addShape(grp3);

    try world.renderThreads(&cam, "csg2.ppm", io, &tracer);

    world.deinit(); // Should free everything
}

fn makePawn(io: Io, allocator: Allocator, options: *DemoOptions) !void {
    var floor = plane(allocator);
    const gray0 = Color{0.1, 0.1, 0.1};
    const gray1 = Color{0.9, 0.9, 0.9};
    floor.material.pattern = checkers(gray0, gray1);
    floor.material.specular = 0;
    floor.material.reflective = 0.3;

    var right_wall = plane(allocator);
    right_wall.itrans = invRotationX(std.math.pi / 2.0);
    right_wall.material.pattern = checkers(gray0, gray1);
    right_wall.material.specular = 0;

    const tracer = Tracer{};

    const world = World.init(
        PointLight{ .position = point(-7, 11, -10), .intensity = Color{1, 1, 1}},
        allocator);

    const cam = Camera.init(options.width, options.height, std.math.pi / 3.0,
                                point(0, 4, -5), point(0,2,0), vector(0, 1, 0));

    const grp = try readObjFile(io, allocator, "../../models/paulin/pawn-chess.obj", &glassMaterial);
    // grp.itrans = invTranslation(0, 0, -3);

    world.scene.addShape(grp);
    world.scene.addShape(floor);
    try world.renderThreads(&cam, "pawn.ppm", io, &tracer);
}

fn makeUtahTeapot(io: Io, allocator: Allocator) !void {
    var floor = plane(allocator);
    const gray0 = Color{0.2, 0.2, 0.2};
    const gray1 = Color{0.6, 0.6, 0.6};
    floor.material.pattern = checkers(gray0, gray1);
    floor.material.specular = 0;

    var right_wall = plane(allocator);
    right_wall.itrans = invRotationX(std.math.pi / 2.0);
    right_wall.material.pattern = checkers(gray0, gray1);
    right_wall.material.specular = 0;

    const world = World.init(
        PointLight{ .position = point(-1, 100, -100), .intensity = Color{1, 1, 1}},
        allocator);

    const cam = Camera.init(600, 300, std.math.pi / 4.0,
                            point(0, 5, -7), point(0,0,-1), vector(0, 1, 0));

    var grp = try readObjFile(io, allocator, "../../models/utah_teapot.obj", &testMaterial);
    grp.itrans = invTranslation(0, 0, -3);

    world.scene.addShape(grp);
    world.scene.addShape(floor);
    try world.render(&cam, "utah_teapot.ppm", io);
}

fn makeSmoothTeapot(io: Io, allocator: Allocator) !void {
    var floor = plane(allocator);
    const gray0 = Color{0.2, 0.2, 0.2};
    const gray1 = Color{0.6, 0.6, 0.6};
    floor.material.pattern = checkers(gray0, gray1);
    floor.material.specular = 0;

    var right_wall = plane(allocator);
    right_wall.itrans = invRotationX(std.math.pi / 2.0);
    right_wall.material.pattern = checkers(gray0, gray1);
    right_wall.material.specular = 0;

    const world = World.init(
        PointLight{ .position = point(-1, 100, -100), .intensity = Color{1, 1, 1}},
        allocator);

    const cam = Camera.init(600, 300, std.math.pi / 4.0,
                                point(0, 5, -7), point(0,0,0), vector(0, 1, 0));

    var grp = try readObjFile(io, allocator, "../../models/newell_teaset/teapot.obj", &testMaterial);
    grp.itrans = invRotationY(-std.math.pi / 2.0);
    const trans = invTranslation(0, 0, -2);
    grp.chainTransf(&trans);

    world.scene.addShape(grp);
    world.scene.addShape(floor);
    try world.render(&cam, "teapot_normals2.ppm", io);
}

fn makeTeapot(io: Io, allocator: Allocator, options: *DemoOptions) !void {
    var floor = plane(allocator);
    const gray0 = Color{0.2, 0.2, 0.2};
    const gray1 = Color{0.6, 0.6, 0.6};
    floor.material.pattern = checkers(gray0, gray1);
    floor.material.specular = 0;

    var right_wall = plane(allocator);
    right_wall.itrans = invRotationX(std.math.pi / 2.0);
    right_wall.material.pattern = checkers(gray0, gray1);
    right_wall.material.specular = 0;

    const tracer = Tracer{};

    const world = World.init(
        PointLight{ .position = point(-1, 100, -100), .intensity = Color{1, 1, 1}},
        allocator);

    const cam = Camera.init(options.width, options.height, std.math.pi / 3.0,
                                point(0, 5, -7), point(0,0,-1), vector(0, 1, 0));

    var grp = try readObjFile(io, allocator, "../../models/teapot.obj", &testMaterial);
    grp.itrans = invTranslation(0, 0, -3);

    world.scene.addShape(grp);
    world.scene.addShape(floor);
    try world.renderThreads(&cam, "teapot.ppm", io, &tracer);
}

fn makePumpkin(io: Io, allocator: Allocator, options: *DemoOptions) !void {
    var floor = plane(allocator);
    const gray0 = Color{0.2, 0.2, 0.2};
    const gray1 = Color{0.6, 0.6, 0.6};
    floor.material.pattern = checkers(gray0, gray1);
    floor.material.specular = 0;

    var right_wall = plane(allocator);
    right_wall.itrans = invRotationX(std.math.pi / 2.0);
    right_wall.material.pattern = checkers(gray0, gray1);
    right_wall.material.specular = 0;

    const tracer = Tracer{};

    const world = World.init(
        PointLight{ .position = point(-1, 100, -100), .intensity = Color{1, 1, 1}},
        allocator);

    const cam = Camera.init(options.width, options.height, std.math.pi / 5.0,
                                point(0, 10, -100), point(0,10,0), vector(0, 1, 0));

    var grp = try readObjFile(io, allocator, "../../models/pumpkin.obj", &testMaterial);
    // const scl = invScaling(0.4, 0.4, 0.4);
    // const rot = invRotationX(std.math.pi / 8.0);
    grp.chainTransf(&invScaling(0.4, 0.4, 0.4));
    grp.chainTransf(&invRotationX(std.math.pi / 8.0));

    world.scene.addShape(grp);
    // world.scene.addShape(floor);
    // try world.render(&cam, "pumpkin.ppm", io);
    try world.renderThreads(&cam, "pumpkin.ppm", io, &tracer);
}
