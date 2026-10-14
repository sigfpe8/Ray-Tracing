//! Bounding Volume Hierachies

const std = @import("std");
const mth = @import("math.zig");
const Float = mth.Float;
const Matrix = mth.Matrix;
const Point = mth.Point;
const Vector = mth.Vector;
const point = mth.point;
const pntEqual = mth.pntEqual;
const matMul = mth.matMul;
const matMulVec = mth.matMulVec;
const INFINITY = mth.INFINITY;

pub const BBox = struct {
    min: Point = point( INFINITY,  INFINITY,  INFINITY,),
    max: Point = point(-INFINITY, -INFINITY, -INFINITY,),

    const Self = @This();

    // Add other box to self
    pub fn addBox(self: *Self, other: *const BBox) void {
        self.min = @min(self.min, other.min);
        self.max = @max(self.max, other.max);
    }

    // Add a point to self
    pub fn addPoint(self: *Self, pnt: Point) void {
        self.min = @min(self.min, pnt);
        self.max = @max(self.max, pnt);
    }

    // Does this box contain a given point?
    pub fn containsPoint(self: *const Self, pnt: Point) bool {
        const v1 = self.min <= pnt;
        const v2 = self.max >= pnt;
        return @reduce(.And, v1) and @reduce(.And, v2);
    }

    // Does this box contain another box?
    pub fn containsBox(self: *const Self, other: *const Self) bool {
        const v1 = self.min <= other.min;
        const v2 = self.min <= other.max;
        const v3 = self.max >= other.min;
        const v4 = self.max >= other.max;
        return @reduce(.And, v1) and @reduce(.And, v2) and
               @reduce(.And, v3) and @reduce(.And, v4);
    }

    // Transform this box according to the given matrix and return it as new box
    pub fn transform(self: *const Self, mat: *const Matrix) BBox {
        const corners = [8]Point {
            .{ self.min[0], self.min[1], self.min[2], 1 },  // self.min
            .{ self.min[0], self.min[1], self.max[2], 1 },
            .{ self.min[0], self.max[1], self.min[2], 1 },
            .{ self.min[0], self.max[1], self.max[2], 1 },
            .{ self.max[0], self.min[1], self.min[2], 1 },
            .{ self.max[0], self.min[1], self.max[2], 1 },
            .{ self.max[0], self.max[1], self.min[2], 1 },
            .{ self.max[0], self.max[1], self.max[2], 1 },  // self.max
        };

        var box = BBox{};
        for (corners) |corner| {
            const pnt: Point = matMulVec(mat, corner);
            box.addPoint(pnt);
        }

        return box;
    }

    pub fn boxEqual(self: *const Self, other: *const Self) bool {
        return pntEqual(self.min, other.min) and
               pntEqual(self.max, other.max);
    }
};

pub fn bbox(_min: Point, _max: Point) BBox {
    return .{
        .min = _min,
        .max = _max,
   };
}

const expect = std.testing.expect;
const obi = @import("object.zig");
const CsgOp = obi.CsgOp;
const csg = obi.csg;
const cylinder = obi.cylinder;
const group = obi.group;
const sphere = obi.sphere;

const trf = @import("transform.zig");
const rotationX = trf.rotationX;
const rotationY = trf.rotationY;
const invScaling = trf.invScaling;
const invTranslation = trf.invTranslation;

const ContainsPointTest = struct {
    pnt: Point,
    res: bool,
};

// For bbox(point(5, -2, 0), point(11, 4, 7))
const containsPointTests = [_]ContainsPointTest {
    .{.pnt = point( 5, -2,  0), .res = true },
    .{.pnt = point(11,  4,  7), .res = true },
    .{.pnt = point( 8,  1,  1), .res = true },
    .{.pnt = point( 3,  0,  3), .res = false },
    .{.pnt = point( 8, -4,  3), .res = false },
    .{.pnt = point( 8,  1, -1), .res = false },
    .{.pnt = point(13,  1,  3), .res = false },
    .{.pnt = point( 8,  5,  3), .res = false },
    .{.pnt = point( 8,  1,  8), .res = false },
};

test "BBox" {
    var box = BBox{};
    box.addPoint(point(-5, 2, 0));
    box.addPoint(point(7, 0, -3));
    try expect(pntEqual(box.min, point(-5, 0, -3)));
    try expect(pntEqual(box.max, point(7, 2, 0)));

    box = bbox(point(-5, -2, 0), point(7, 4, 4));
    const box2 = bbox(point(8, -7, -2), point(14, 2, 8));
    box.addBox(&box2);
    try expect(pntEqual(box.min, point(-5, -7, -2)));
    try expect(pntEqual(box.max, point(14, 4, 8)));
}

test "containsPoint" {
    const box = bbox(point(5, -2, 0), point(11, 4, 7));
    for (containsPointTests) |tst| {
        const res = box.containsPoint(tst.pnt);
        try expect(res == tst.res);
    }
}

const ContainsBoxTest = struct {
    min: Point,
    max: Point,
    res: bool,
};

// For bbox(point(5, -2, 0), point(11, 4, 7))
const containsBoxTests = [_]ContainsBoxTest {
    .{ .min = point(5, -2,  0), .max = point(11,  4,  7), .res = true },
    .{ .min = point(6, -1,  1), .max = point(10,  3,  6), .res = true },
    .{ .min = point(4, -3, -1), .max = point(10,  3,  6), .res = false },
    .{ .min = point(6, -1,  1), .max = point(12,  5,  8), .res = false },
};

test "containsBox" {
    const box = bbox(point(5, -2, 0), point(11, 4, 7));
    for (containsBoxTests) |tst| {
        const box2 = bbox(tst.min, tst.max);
        const res = box.containsBox(&box2);
        try expect(res == tst.res);
    }
}

test "transforming a BBox" {
    const ang = std.math.pi / 4.0;
    const mat = matMul(&rotationX(ang), &rotationY(ang));
    var box = bbox(point(-1, -1, -1), point(1, 1, 1));
    const tbox = box.transform(&mat);
    var rbox = bbox(point(-1.4142135, -1.7071067, -1.7071067), point(1.4142135, 1.7071067, 1.7071067));
    try expect(tbox.boxEqual(&rbox));

    const allocator = std.testing.allocator;
    var shape = sphere(allocator);
    defer shape.deinit(allocator);
    mth.matMulLeft(&shape.itrans, &invScaling(0.5, 2, 4));
    mth.matMulLeft(&shape.itrans, &invTranslation(1, -3, 5));

    box = shape.parentSpaceBoundsOf();
    rbox = bbox(point(0.5, -5, 1), point(1.5, -1, 9));
    try expect(box.boxEqual(&rbox));

}

test "BBpx of CSG objects" {
    const allocator = std.testing.allocator;

    const left = sphere(allocator);
    var right = sphere(allocator);
    mth.matMulLeft(&right.itrans, &invTranslation(2, 3, 4));

    const shape = csg(allocator, CsgOp.csg_diff, left, right);
    defer shape.deinit(allocator);  // Frees left + right

    const box = shape.parentSpaceBoundsOf();
    const rbox = bbox(point(-1, -1, -1), point(3, 4, 5));
    try expect(box.boxEqual(&rbox));
}

test "BBpx of Group objects" {
    const allocator = std.testing.allocator;

    var s = sphere(allocator);
    mth.matMulLeft(&s.itrans, &invScaling(2, 2, 2));
    mth.matMulLeft(&s.itrans, &invTranslation(2, 5, -3));

    var c = cylinder(allocator, -2, 2, true);
    mth.matMulLeft(&c.itrans, &invScaling(0.5, 1, 0.5));
    mth.matMulLeft(&c.itrans, &invTranslation(-4, -1, 4));

    var shape = group(allocator);
    defer shape.deinit(allocator);  // Frees s + c
    shape.addShape(s);
    shape.addShape(c);

    const box = shape.parentSpaceBoundsOf();
    const rbox = bbox(point(-4.5, -3, -5), point(4, 7, 4.5));
    try expect(box.boxEqual(&rbox));
}