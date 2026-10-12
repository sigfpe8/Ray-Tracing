const mth = @import("math.zig");
const Point = mth.Point;
const Matrix = mth.Matrix;
const matIdentify = mth.matIdentity;
const matMulVec = mth.matMulVec;

const mtl = @import("material.zig");
const Color = mtl.Color;
const Material = mtl.Material;
const black = mtl.black;
const white = mtl.white;
const colScale = mtl.colScale;

const obi = @import("object.zig");
const Object = obi.Object;

const PatternFn = *const fn (self: *const Pattern, pnt: Point) Color;

pub const Pattern = struct {
    active: bool = false,
    colorA: Color = black,
    colorB: Color = white,
    colorFn: PatternFn = undefined,
    itrans: Matrix = undefined,

    pub fn new(colorA: Color, colorB: Color, colorFn: PatternFn) Pattern {
        return .{
            .active = true,
            .colorA = colorA,
            .colorB = colorB,
            .colorFn = colorFn,
            .itrans = matIdentify(),
        };
    }

    pub fn colorAt(self: *const Pattern, world_pnt: Point) Color {
        // This pattern is a field of a Material
        const material: *const Material = @fieldParentPtr("pattern", self);
        // This material is a field of an Object
        const obj: *const Object = @fieldParentPtr("material", material);
        const obj_pnt = matMulVec(&obj.itrans, world_pnt);
        const pat_pnt = matMulVec(&self.itrans, obj_pnt);
        return self.colorFn(self, pat_pnt);
    }
};

pub const PatternType = enum {
    patNone,
    patCheckers,
    patGradient,
    patRings,
    patStripes,
};

/// Stripes of alternating colors depending only on x -------------------------
pub fn stripes(colorA: Color, colorB: Color) Pattern {
    return Pattern.new(colorA, colorB, &stripes_colorAt);
}

fn stripes_colorAt(self: *const Pattern, pnt: Point) Color {
    // Checks if floor(x) % 2 is even or odd
    const tmp: isize = @mod(@as(isize,@intFromFloat(@floor(pnt[0]))),2);
    return if (tmp == 0) self.colorA else self.colorB;
}

/// Checkers depending on x, y and z ------------------------------------------
pub fn checkers(colorA: Color, colorB: Color) Pattern {
    return Pattern.new(colorA, colorB, &checkers_colorAt);
}

fn checkers_colorAt(self: *const Pattern, pnt: Point) Color {
    // Checks if floor(x) % 2 is even or odd
    const tmp: isize = @mod(@as(isize,@intFromFloat(@floor(pnt[0]))) +
                            @as(isize,@intFromFloat(@floor(pnt[1]))) +
                            @as(isize,@intFromFloat(@floor(pnt[2])))
                        ,2);
    return if (tmp == 0) self.colorA else self.colorB;
}

/// Gradient from color A to color B depending only on x ----------------------
pub fn gradient(colorA: Color, colorB: Color) Pattern {
    return Pattern.new(colorA, colorB, &gradient_colorAt);
}

fn gradient_colorAt(self: *const Pattern, pnt: Point) Color {
    // Checks if floor(x) % 2 is even or odd
    return self.colorA + colScale(self.colorB - self.colorA, pnt[0] - @floor(pnt[0]));
}

/// Rings in the XZ plane depending on the distance to the origin -------------
pub fn rings(colorA: Color, colorB: Color) Pattern {
    return Pattern.new(colorA, colorB, &rings_colorAt);
}

fn rings_colorAt(self: *const Pattern, pnt: Point) Color {
    // Checks if floor(distance to origin) % 2 is even or odd
    const dist = @floor(@sqrt(pnt[0]*pnt[0]+pnt[2]*pnt[2]));
    const tmp: isize = @mod(@as(isize,@intFromFloat(dist)),2);
    return if (tmp == 0) self.colorA else self.colorB;
}

/// Test pattern
pub fn test_pattern() Pattern {
    return Pattern.new(black, white, &test_pattern_colorAt);
}

fn test_pattern_colorAt(self: *const Pattern, pnt: Point) Color {
    _ = self;
    return Color{pnt[0], pnt[1], pnt[2]};
}

const std = @import("std");
const expect = std.testing.expect;
const sphere = obi.sphere;
const plane = obi.plane;
const trf = @import("transform.zig");
const invScaling = trf.invScaling;
const invTranslation = trf.invTranslation;
const point = mth.point;
const colEqual = mtl.colEqual;

test "Test Pattern" {
    const allocator = std.testing.allocator;
    // A pattern with an object transformation
    var shape = sphere(allocator);
    shape.itrans = invScaling(2, 2, 2);
    shape.material.pattern = test_pattern();
    var color = shape.material.pattern.colorAt(point(2,3,4));
    try expect(colEqual(color, Color{1, 1.5, 2}));
    shape.deinit(allocator);

    // A pattern with a pattern transformation
    shape = sphere(allocator);
    shape.material.pattern = test_pattern();
    shape.material.pattern.itrans = invScaling(2, 2, 2);
    color = shape.material.pattern.colorAt(point(2,3,4));
    try expect(colEqual(color, Color{1, 1.5, 2}));
    shape.deinit(allocator);

    // A pattern with both an object and a pattern transformation
    shape = sphere(allocator);
    shape.itrans = invScaling(2, 2, 2);
    shape.material.pattern = test_pattern();
    shape.material.pattern.itrans = invTranslation(0.5, 1, 1.5);
    color = shape.material.pattern.colorAt(point(2.5,3,3.5));
    try expect(colEqual(color, Color{0.75, 0.5, 0.25}));
    shape.deinit(allocator);
}

test "Gradient" {
    const allocator = std.testing.allocator;
    // Gradient pattern
    var shape = plane(allocator);
    defer shape.deinit(allocator);
    shape.material.pattern = gradient(white, black);
    var color = shape.material.pattern.colorAt(point(0, 0, 0));
    try expect(colEqual(color, white));
    color = shape.material.pattern.colorAt(point(0.25, 0, 0));
    try expect(colEqual(color, Color{0.75, 0.75, 0.75}));
    color = shape.material.pattern.colorAt(point(0.5, 0, 0));
    try expect(colEqual(color, Color{0.5, 0.5, 0.5}));
    color = shape.material.pattern.colorAt(point(0.75, 0, 0));
    try expect(colEqual(color, Color{0.25, 0.25, 0.25}));
}

test "Rings" {
    const allocator = std.testing.allocator;
    var shape = plane(allocator);
    defer shape.deinit(allocator);
    shape.material.pattern = rings(white, black);
    var color = shape.material.pattern.colorAt(point(0, 0, 0));
    try expect(colEqual(color, white));
    color = shape.material.pattern.colorAt(point(1, 0, 0));
    try expect(colEqual(color, black));
    color = shape.material.pattern.colorAt(point(0, 0, 1));
    try expect(colEqual(color, black));
    // 0.708 = just slightly more than @sqrt(2)/2
    color = shape.material.pattern.colorAt(point(0.708, 0, 0.708));
    try expect(colEqual(color, black));
}

test "Checkers" {
     const allocator = std.testing.allocator;
   var shape = sphere(allocator);
   defer shape.deinit(allocator);
    shape.material.pattern = checkers(white, black);
    // Checkers should repeat in x
    var color = shape.material.pattern.colorAt(point(0, 0, 0));
    try expect(colEqual(color, white));
    color = shape.material.pattern.colorAt(point(0.99, 0, 0));
    try expect(colEqual(color, white));
    color = shape.material.pattern.colorAt(point(1.01, 0, 0));
    try expect(colEqual(color, black));

    // Checkers should repeat in y
    color = shape.material.pattern.colorAt(point(0, 0, 0));
    try expect(colEqual(color, white));
    color = shape.material.pattern.colorAt(point(0, 0.99, 0));
    try expect(colEqual(color, white));
    color = shape.material.pattern.colorAt(point(0, 1.01, 0));
    try expect(colEqual(color, black));

    // Checkers should repeat in z
    color = shape.material.pattern.colorAt(point(0, 0, 0));
    try expect(colEqual(color, white));
    color = shape.material.pattern.colorAt(point(0, 0,0.99));
    try expect(colEqual(color, white));
    color = shape.material.pattern.colorAt(point(0, 0,1.01));
    try expect(colEqual(color, black));
}