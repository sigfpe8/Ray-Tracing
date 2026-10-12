//! Bounding Volume Hierachies

const std = @import("std");
const mth = @import("math.zig");
const Float = mth.Float;
const Point = mth.Point;
const point = mth.point;
const pntEqual = mth.pntEqual;
const INFINITY = mth.INFINITY;

const BoundingBox = struct {
    min: Point = point( INFINITY,  INFINITY,  INFINITY,),
    max: Point = point(-INFINITY, -INFINITY, -INFINITY,),

    const Self = @This();

    // Add other box to self
    pub fn addBox(self: *Self, other: *const BoundingBox) void {
        self.min = @min(self.min, other.min);
        self.max = @max(self.max, other.max);
    }

    // Add a point to self
    pub fn addPoint(self: *Self, pnt: Point) void {
        self.min = @min(self.min, pnt);
        self.max = @max(self.max, pnt);
    }

    pub fn containsPoint(self: *const Self, pnt: Point) bool {
        const v1 = self.min <= pnt;
        const v2 = self.max >= pnt;
        return @reduce(.And, v1) and @reduce(.And, v2);
    }

    pub fn containsBox(self: *const Self, other: *const Self) bool {
        const v1 = self.min <= other.min;
        const v2 = self.min <= other.max;
        const v3 = self.max >= other.min;
        const v4 = self.max >= other.max;
        return @reduce(.And, v1) and @reduce(.And, v2) and
               @reduce(.And, v3) and @reduce(.And, v4);
    }

    pub fn boxEqual(self: *const Self, other: *const Self) bool {
        return pntEqual(self.min, other.min) and
               pntEqual(self.max, other.max);
    }
};

pub fn bbox(_min: Point, _max: Point) BoundingBox {
    return .{
        .min = _min,
        .max = _max,
   };
}

const expect = std.testing.expect;

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

test "BoundingBox" {
    var box = BoundingBox{};
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