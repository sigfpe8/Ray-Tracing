const mth = @import("math.zig");
const Float = mth.Float;
const Vector = mth.Vector;
const Matrix = mth.Matrix;
const Point = mth.Point;
const vector = mth.vector;
const point = mth.point;
const cross = mth.cross;
const vecEqual = mth.vecEqual;
const vecUnit = mth.vecUnit;
const matEqual = mth.matEqual;
const matMul = mth.matMul;
const matMulVec = mth.matMulVec;

/// Return a matrix that performs translation
pub fn translation(x: Float, y: Float, z: Float) Matrix {
    return .{
        .{ 1, 0, 0, x },
        .{ 0, 1, 0, y },
        .{ 0, 0, 1, z },
        .{ 0, 0, 0, 1 },
    };
}

pub fn invTranslation(x: Float, y: Float, z: Float) Matrix {
    return .{
        .{ 1, 0, 0, -x },
        .{ 0, 1, 0, -y },
        .{ 0, 0, 1, -z },
        .{ 0, 0, 0,  1 },
    };
}

/// Return a matrix that performs scaling
pub fn scaling(x: Float, y: Float, z: Float) Matrix {
    return .{
        .{ x, 0, 0, 0 },
        .{ 0, y, 0, 0 },
        .{ 0, 0, z, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn invScaling(x: Float, y: Float, z: Float) Matrix {
    // TODO: verify/assert that x,y,y != 0
    return .{
        .{ 1.0/x,  0,    0,   0 },
        .{ 0,    1.0/y,  0,   0 },
        .{ 0,      0,  1.0/z, 0 },
        .{ 0,      0,    0,   1 },
    };
}

/// Return a matrix that performs a rotation around an axis
/// by an angle 'r' given in radians
pub fn rotationX(r: Float) Matrix {
    return .{
        .{ 1,    0,        0,     0 },
        .{ 0, @cos(r), -@sin(r),  0 },
        .{ 0, @sin(r),  @cos(r),  0 },
        .{ 0,    0,        0,     1 },
    };
}

pub fn invRotationX(r: Float) Matrix {
    return .{
        .{ 1,    0,         0,      0 },
        .{ 0, @cos(-r), -@sin(-r),  0 },
        .{ 0, @sin(-r),  @cos(-r),  0 },
        .{ 0,    0,         0,      1 },
    };
}

pub fn rotationY(r: Float) Matrix {
    return .{
        .{  @cos(r),  0,  @sin(r),  0 },
        .{     0,     1,     0,     0 },
        .{ -@sin(r),  0,  @cos(r),  0 },
        .{     0,     0,     0,     1 },
    };
}

pub fn invRotationY(r: Float) Matrix {
    return .{
        .{  @cos(-r),  0,  @sin(-r),  0 },
        .{     0,      1,     0,      0 },
        .{ -@sin(-r),  0,  @cos(-r),  0 },
        .{     0,      0,     0,      1 },
    };
}

pub fn rotationZ(r: Float) Matrix {
    return .{
        .{  @cos(r), -@sin(r),  0,  0 },
        .{  @sin(r),  @cos(r),  0,  0 },
        .{     0,        0,     1,  0 },
        .{     0,        0,     0,  1 },
    };
}

pub fn invRotationZ(r: Float) Matrix {
    return .{
        .{  @cos(-r), -@sin(-r),  0,  0 },
        .{  @sin(-r),  @cos(-r),  0,  0 },
        .{     0,        0,       1,  0 },
        .{     0,        0,       0,  1 },
    };
}

/// Return a matrix that performs shearing
pub fn shearing(xy: Float, xz: Float, yx: Float, yz: Float, zx: Float, zy: Float) Matrix {
    return .{
        .{  1,  xy,  xz,  0 },
        .{ yx,   1,  yz,  0 },
        .{ zx,  zy,   1,  0 },
        .{  0,   0,   0,  1 },
    };
}

/// Chain (i.e. multiply) a list of transformations into a single matrix
pub fn chain(trs: []const *const Matrix) Matrix {
    var mat: Matrix = undefined;

    if (trs.len > 0) {
        mat = trs[0].*;
        for (trs[1..]) |m| {
            mat = matMul(m, &mat);
        }
    } else {
        mat = mth.matIdentity();
    }

    return mat;
}

/// View transformation
pub fn viewTransform(from: Point, to: Point, up: Vector) Matrix {
    const forward = vecUnit(to - from);
    const upn = vecUnit(up);
    const left = cross(forward, upn);
    const true_up = cross(left, forward);
    var orientation: Matrix = .{
        left,
        true_up,
        -forward,
        .{ 0, 0, 0, 1},
    };
    const transl = translation(-from[0], -from[1], -from[2]);
    return matMul(&orientation, &transl);
}

const std = @import("std");
const expect = std.testing.expect;

test "Transformations" {
    var p: Point = undefined;       // A point
    var tp: Point = undefined;      // Point after transformation
    var ip: Point = undefined;      // Point after inverse transformation
    var tr: Matrix = undefined;     // A transformation
    var it: Matrix = undefined;     // The inverse transformation

    // Translation
    p = point(-3, 4, 5);
    tr = translation(5, -3, 2);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(2, 1, 7)));
    // Inverse translation
    it = invTranslation(5, -3, 2);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));
    // Using matrix inversion
    it = try mth.matInverse(&tr);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));

    // Scaling
    p = point(-4, 6, 8);
    tr = scaling(2, 3, 4);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(-8, 18, 32)));
    // Inverse scaling
    it = invScaling(2, 3, 4);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));
    // Using matrix inversion
    it = try mth.matInverse(&tr);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));

    const pi = std.math.pi;
    // Rotation around the X axis
    p = point(0, 1, 0);
    // Half quarter
    tr = rotationX(pi / 4.0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(0, @sqrt(2.0)/2.0, @sqrt(2.0)/2.0)));
    // Full quarter
    tr = rotationX(pi / 2.0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(0, 0, 1)));
    // Inverse rotation
    it = invRotationX(pi / 2.0);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));
    // Using matrix inversion
    it = try mth.matInverse(&tr);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));

    // Rotation around the Y axis
    p = point(0, 0, 1);
    // Half quarter
    tr = rotationY(pi / 4.0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(@sqrt(2.0)/2.0, 0, @sqrt(2.0)/2.0)));
    // Full quarter
    tr = rotationY(pi / 2.0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(1, 0, 0)));
    // Inverse rotation
    it = invRotationY(pi / 2.0);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));
    // Using matrix inversion
    it = try mth.matInverse(&tr);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));

    // Rotation around the Z axis
    p = point(0, 1, 0);
    // Half quarter
    tr = rotationZ(pi / 4.0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(-@sqrt(2.0)/2.0, @sqrt(2.0)/2.0, 0)));
    // Full quarter
    tr = rotationZ(pi / 2.0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(-1, 0, 0)));
    // Inverse rotation
    it = invRotationZ(pi / 2.0);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));
    // Using matrix inversion
    it = try mth.matInverse(&tr);
    ip = matMulVec(&it, tp);
    try expect(vecEqual(ip, p));

    // Shearing
    // Moves x in proportion to z
    p = point(2, 3, 4);
    tr = shearing(0, 1, 0, 0, 0, 0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(6, 3, 4)));
    // Moves y in proportion to x
    tr = shearing(0, 0, 1, 0, 0, 0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(2, 5, 4)));
    // Moves y in proportion to z
    tr = shearing(0, 0, 0, 1, 0, 0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(2, 7, 4)));
    // Moves z in proportion to x
    tr = shearing(0, 0, 0, 0, 1, 0);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(2, 3, 6)));
    // Moves z in proportion to y
    tr = shearing(0, 0, 0, 0, 0, 1);
    tp = matMulVec(&tr, p);
    try expect(vecEqual(tp, point(2, 3, 7)));

    // Chaining
    const trA = rotationX(pi / 2.0);
    const trB = scaling(5, 5, 5);
    const trC = translation(10, 5, 7);
    p = point(1, 0, 1);
    // Perform each transformation individually
    tp = matMulVec(&trA, p);
    try expect(vecEqual(tp, point(1, -1, 0)));
    tp = matMulVec(&trB, tp);
    try expect(vecEqual(tp, point(5, -5, 0)));
    tp = matMulVec(&trC, tp);
    try expect(vecEqual(tp, point(15, 0, 7)));

    const tlist: [3]*const Matrix = .{
        &trA,
        &trB,
        &trC,
    };
    // Now chain them into a single matrix
    tr = chain(&tlist); 
    tp = matMulVec(&tr, p);
    // And the result of applying it should give the same result as above
    try expect(vecEqual(tp, point(15, 0, 7)));
}

test "View Transformation" {
    const from = point(1, 3, 2);
    const to = point(4, -2, 8);
    const up = vector(1, 1, 0);

    const trf = viewTransform(from, to, up);

    const mat: Matrix = .{
        .{-0.50709,   0.50709,   0.67612,  -2.36643},
        .{ 0.76772,   0.60609,   0.12122,  -2.82843},
        .{-0.35857,   0.59761,  -0.71714,   0.00000},
        .{ 0.00000,   0.00000,   0.00000,   1.00000},
    };

    try expect(matEqual(&trf, &mat));
}