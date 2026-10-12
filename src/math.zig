//! The vectors and matrices in this file are streamlined for use in graphics applications.
//! Therefore:
//!    * all elements are of type Float
//!    * all vectors have length 4
//!    * all matrices are 4x4
//!    * vectors use the @Vector() type so that SIMD instructions can be used when available
//!    * matrices are fixed arrays of @Vectors()
const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Reader = Io.Reader;
const Writer = Io.Writer;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

/// It is certainly possible to define a generic struct with
/// comptime vector length and instantiate types for len=3
/// and len=4. This has the advantage of simplifying some things,
/// like the dot product for example, which can be defined only
/// once and works for all vector lengths. However, you lose
/// the ability to use '+' directly to add vectors and need to
/// resort to a method, i.e. `v1.add(v2)` instead of `v1 + v2`.
/// I think the latter is much nicer and happens all over the
/// code, so this is why I use 'naked' vectors.

pub const Float = f32;
pub const EPSILON = 0.00001;
pub const INFINITY = std.math.floatMax(Float);

pub const Tuple = @Vector(4, Float);
pub const Vector = Tuple;
pub const Point = Tuple;

pub const MatrixError = error{
    MatrixIsNotInvertible,
};

/// Create a Vector{}
pub fn vector(x: Float, y:Float, z: Float) Vector {
    return Vector{x, y, z, 0};
}

/// Create a Point{}
pub fn point(x: Float, y:Float, z: Float) Point {
    return Point{x, y, z, 1};
}

/// Dot product between two vectors
pub inline fn dot(a: Vector, b: Vector) Float {
    return @reduce(.Add, a * b);
}

/// Cross product between two vectors
pub fn cross(a: Vector, b: Vector) Vector {
    const a_x, const a_y, const a_z, _ = a;
    const b_x, const b_y, const b_z, _ = b;

    return Vector{a_y * b_z - a_z * b_y,
                  a_z * b_x - a_x * b_z,
                  a_x * b_y - a_y * b_x,
                  0};
}

/// Multiply a vector by a scalar
pub fn vecScale(v: Vector, s: Float) Vector {
    const tv: Vector = @splat(s);
    return v * tv;
}

/// Checks whether two vectors are equal within the epsilon tolerance
pub fn vecEqual(v1: Vector, v2: Vector) bool {
    const tv = @abs(v1 - v2) < @as(Vector, @splat(EPSILON));
    return @reduce(.And, tv);
}

/// Unit vector in the direction of the given vector
pub fn vecUnit(v: Vector) Vector {
    const vl = @as(Vector, @splat(vecMag(v)));
    return v / vl;
}

/// Vector magnitude
pub fn vecMag(v: Vector) Float {
    return @sqrt(dot(v, v));
}

/// Vector magnitude squared
pub fn vecMag2(v: Vector) Float {
    return dot(v, v);
}

/// Checks whether two points are equal within the epsilon tolerance
pub fn pntEqual(p1: Point, p2: Point) bool {
    const tv = @abs(p1 - p2) < @as(Point, @splat(EPSILON));
    return @reduce(.And, tv);
}


const expect = std.testing.expect;
const expectError = std.testing.expectError;
const approxEqAbs = std.math.approxEqAbs;

test "Vector" {
    const a = vector(1, 2, 3);
    const b = vector(2, 3, 4);
    var mag: Float = undefined;

    mag = vecMag(vector(1, 0, 0));
    try expect(approxEqAbs(Float, mag, 1, EPSILON));
    mag = vecMag(vector(0, 1, 0));
    try expect(approxEqAbs(Float, mag, 1, EPSILON));
    mag = vecMag(vector(0, 0, 1));
    try expect(approxEqAbs(Float, mag, 1, EPSILON));
    mag = vecMag(a);
    try expect(approxEqAbs(Float, mag, @sqrt(14), EPSILON));

    const uv = vecUnit(a);
    try expect(vecEqual(uv, vector(0.26726, 0.53452, 0.80178)));

    var cv = cross(a, b);
    try expect(vecEqual(cv, vector(-1, 2, -1)));

    cv = cross(b, a);
    try expect(vecEqual(cv, vector(1, -2, 1)));

    const dp = dot(a, b);
    try expect(approxEqAbs(Float, dp, 20, EPSILON));
}


/// 4x4 Float Matrices
pub const Matrix = [4]Vector;

/// Sometimes it may be necessary to convert vectors to arrays
pub const Array = [4]Float;
pub const ArrayMatrix = [4]Array;

pub fn matZeros() Matrix {
    return .{
        .{0, 0, 0, 0},
        .{0, 0, 0, 0},
        .{0, 0, 0, 0},
        .{0, 0, 0, 0},
    };
}

pub fn matIdentity() Matrix {
    return .{
        .{1, 0, 0, 0},
        .{0, 1, 0, 0},
        .{0, 0, 1, 0},
        .{0, 0, 0, 1},
    };
}

/// Return a colum of a matrix as a vector
/// Vector indices must be comptime-known
pub inline fn matColumn(mat: *const Matrix, comptime col: usize) Vector {
    return .{ mat[0][col], mat[1][col], mat[2][col], mat[3][col] };
}

/// Return the transpose of a matrix
pub fn matTranspose(mat: *const Matrix) Matrix {
    return .{
        matColumn(mat, 0),
        matColumn(mat, 1),
        matColumn(mat, 2),
        matColumn(mat, 3),
    };
}

/// Multiply two matrices (A * B)
pub fn matMul(mat1: *const Matrix, mat2: *const Matrix) Matrix {
    const row = mat1;
    const col = matTranspose(mat2);

    return .{
        .{dot(row[0],col[0]), dot(row[0],col[1]), dot(row[0],col[2]), dot(row[0],col[3])},
        .{dot(row[1],col[0]), dot(row[1],col[1]), dot(row[1],col[2]), dot(row[1],col[3])},
        .{dot(row[2],col[0]), dot(row[2],col[1]), dot(row[2],col[2]), dot(row[2],col[3])},
        .{dot(row[3],col[0]), dot(row[3],col[1]), dot(row[3],col[2]), dot(row[3],col[3])},
    };
}

/// Multiply two matrices (A x B) updating the one on the left (A = A x B)
pub fn matMulLeft(matL: *Matrix, matR: *const Matrix) void {
    const row = matL;
    const col = matTranspose(matR);

    const r0 = .{dot(row[0],col[0]), dot(row[0],col[1]), dot(row[0],col[2]), dot(row[0],col[3])};
    const r1 = .{dot(row[1],col[0]), dot(row[1],col[1]), dot(row[1],col[2]), dot(row[1],col[3])};
    const r2 = .{dot(row[2],col[0]), dot(row[2],col[1]), dot(row[2],col[2]), dot(row[2],col[3])};
    const r3 = .{dot(row[3],col[0]), dot(row[3],col[1]), dot(row[3],col[2]), dot(row[3],col[3])};

    matL[0] = r0;
    matL[1] = r1;
    matL[2] = r2;
    matL[3] = r3;
}

/// Multiply two matrices (A x B) updating the one on the right (B = A x B)
pub fn matMulRight(matL: *const Matrix, matR: *Matrix) void {
    const row = matL;
    const col = matTranspose(matR);

    matR[0] = .{dot(row[0],col[0]), dot(row[0],col[1]), dot(row[0],col[2]), dot(row[0],col[3])};
    matR[1] = .{dot(row[1],col[0]), dot(row[1],col[1]), dot(row[1],col[2]), dot(row[1],col[3])};
    matR[2] = .{dot(row[2],col[0]), dot(row[2],col[1]), dot(row[2],col[2]), dot(row[2],col[3])};
    matR[3] = .{dot(row[3],col[0]), dot(row[3],col[1]), dot(row[3],col[2]), dot(row[3],col[3])};
}

/// Convert matrix to arrays for easier random access
/// (e.g. calculating the determinant). Arrays can have
/// runtime-known indices but vectors cannot.
pub fn matToArray(mat: *const Matrix) ArrayMatrix {
    return .{
        mat[0],
        mat[1],
        mat[2],
        mat[3],
    };
}
 
/// Return the cofactor for a given (row, col)
pub fn matCoFactor(mat: *const ArrayMatrix, row: usize, col: usize) Float {
    const a = mat;
    var r1: usize = undefined;
    var r2: usize = undefined;
    var r3: usize = undefined;
    switch (row) {
        0 => { r1 = 1; r2 = 2; r3 = 3; }, 
        1 => { r1 = 0; r2 = 2; r3 = 3; }, 
        2 => { r1 = 0; r2 = 1; r3 = 3; },
        3 => { r1 = 0; r2 = 1; r3 = 2; },
        else => unreachable,
    }

    var c1: usize = undefined;
    var c2: usize = undefined;
    var c3: usize = undefined;
    switch (col) {
        0 => { c1 = 1; c2 = 2; c3 = 3; }, 
        1 => { c1 = 0; c2 = 2; c3 = 3; }, 
        2 => { c1 = 0; c2 = 1; c3 = 3; },
        3 => { c1 = 0; c2 = 1; c3 = 2; },
        else => unreachable,
    }
    // a11 * (a22*a33 - a23*a32) - a12 * (a21*a33 - a23*a31) + a13 * (a21*a32 - a22*a31)
    const minor =  a[r1][c1] * (a[r2][c2]*a[r3][c3] - a[r2][c3]*a[r3][c2])
                      - a[r1][c2] * (a[r2][c1]*a[r3][c3] - a[r2][c3]*a[r3][c1])
                      + a[r1][c3] * (a[r2][c1]*a[r3][c2] - a[r2][c2]*a[r3][c1]);

    // Cofactor = ((-1)^(row+col)) * minor
    return if (((row+col) & 1) == 0) minor else -minor;
}

pub fn matDet(mat: *const Matrix) Float {
    const m = matToArray(mat);
    const co0 = matCoFactor(&m, 0, 0);
    const co1 = matCoFactor(&m, 0, 1);
    const co2 = matCoFactor(&m, 0, 2);
    const co3 = matCoFactor(&m, 0, 3);
    return m[0][0] * co0 + m[0][1] * co1 + m[0][2] * co2 + m[0][3] * co3;
}

/// Multiply a matrix by a vector on the right
pub fn matMulVec(mat: *const Matrix, vec: Vector) Vector {
    return .{
        dot(mat[0], vec),
        dot(mat[1], vec),
        dot(mat[2], vec),
        dot(mat[3], vec),
    };
}

pub fn matInverse(mat: *const Matrix) !Matrix {
    // Don't call matDet() here because we will need the cofactors for row 0 anyway
    const m = matToArray(mat);
    const co00 = matCoFactor(&m, 0, 0);
    const co01 = matCoFactor(&m, 0, 1);
    const co02 = matCoFactor(&m, 0, 2);
    const co03 = matCoFactor(&m, 0, 3);
    const det = m[0][0] * co00 + m[0][1] * co01 + m[0][2] * co02 + m[0][3] * co03;

    if (approxEqAbs(Float, det, 0, EPSILON)) {
        return MatrixError.MatrixIsNotInvertible;
    }

    const co10 = matCoFactor(&m, 1, 0);
    const co11 = matCoFactor(&m, 1, 1);
    const co12 = matCoFactor(&m, 1, 2);
    const co13 = matCoFactor(&m, 1, 3);

    const co20 = matCoFactor(&m, 2, 0);
    const co21 = matCoFactor(&m, 2, 1);
    const co22 = matCoFactor(&m, 2, 2);
    const co23 = matCoFactor(&m, 2, 3);

    const co30 = matCoFactor(&m, 3, 0);
    const co31 = matCoFactor(&m, 3, 1);
    const co32 = matCoFactor(&m, 3, 2);
    const co33 = matCoFactor(&m, 3, 3);

    return .{
        .{co00/det, co10/det, co20/det, co30/det},
        .{co01/det, co11/det, co21/det, co31/det},
        .{co02/det, co12/det, co22/det, co32/det},
        .{co03/det, co13/det, co23/det, co33/det},
    };
}

pub fn matEqual(mat1: *const Matrix, mat2: *const Matrix) bool {
    var i: usize = 0;

    while (i < 4) : (i += 1) {
        if (!vecEqual(mat1[i], mat2[i])) {
            return false;
        }
    }
    return true;
}

pub fn matPrint(mat: *const Matrix, writer: *Writer) !void {
    for (mat) |*row| {
        try writer.print("{d: >8.5} {d: >8.5} {d: >8.5} {d: >8.5}\n",
                    .{row[0], row[1], row[2], row[3]});
    }
}

pub fn matArrayPrint(mat: *const ArrayMatrix, writer: *Writer) !void {
    for (mat) |*row| {
        try writer.print("{d: >6.2} {d: >6.2} {d: >6.2} {d: >6.2}\n",
                    .{row[0], row[1], row[2], row[3]});
    }
}

test "Matrix"{
    const ident = matIdentity();
    const mat1: Matrix = .{
        .{ 1,  2,  3,  4},
        .{ 5,  6,  7,  8},
        .{ 9, 10, 11, 12},
        .{13, 14, 15, 16},
    };
    const mat1t: Matrix = .{
        .{ 1,  5,  9, 13},
        .{ 2,  6, 10, 14},
        .{ 3,  7, 11, 15},
        .{ 4,  8, 12, 16},
    };
    const mat2 = matTranspose(&mat1);
    try expect(matEqual(&mat2, &mat1t));

    const mat3: Matrix = .{
        .{ -2,  -8,  3,  5 },
        .{ -3,   1,  7,  3 },
        .{  1,   2, -9,  6 },
        .{ -6,   7,  7, -9 },
    };
    const mat3a = matToArray(&mat3);
    const co0 = matCoFactor(&mat3a, 0, 0);
    const co1 = matCoFactor(&mat3a, 0, 1);
    const co2 = matCoFactor(&mat3a, 0, 2);
    const co3 = matCoFactor(&mat3a, 0, 3);

    try expect(approxEqAbs(Float, co0, 690, EPSILON));
    try expect(approxEqAbs(Float, co1, 447, EPSILON));
    try expect(approxEqAbs(Float, co2, 210, EPSILON));
    try expect(approxEqAbs(Float, co3, 51, EPSILON));

    const det = matDet(&mat3);
    try expect(approxEqAbs(Float, det, -4071, EPSILON));

    // Invertible matrices
    const mat4: Matrix = .{
        .{ -5,  2,  6, -8 },
        .{  1, -5,  1,  8 },
        .{  7,  7, -6, -7 },
        .{  1, -3,  7,  4 },
    };
    const mat4i: Matrix = .{
        .{  0.21805,  0.45113,  0.24060, -0.04511 },
        .{ -0.80827, -1.45677, -0.44361,  0.52068 },
        .{ -0.07895, -0.22368, -0.05263,  0.19737 },
        .{ -0.52256, -0.81391, -0.30075,  0.30639 },
    };
    const mat5 = try matInverse(&mat4);
    try expect(matEqual(&mat5, &mat4i));

    // Matrix x Inverse = Identity
    const mat6: Matrix = matMul(&mat4, &mat5);
    try expect(matEqual(&mat6, &ident));

    // Singlular matrices
    var sing: Matrix = .{
        .{ -5,  2,  6, -8 },
        .{  1, -5,  1,  8 },
        .{  7,  7, -6, -7 },
        .{-10,  4, 12,-16 },    // (row 0) * 2
    };
    try expectError(MatrixError.MatrixIsNotInvertible, matInverse(&sing));

    sing = .{
        .{ -4,  2, -2, -3 },
        .{  9,  8,  7,  6 },
        .{  5,  4,  3,  2 },
        .{  0,  0,  0,  0 },    // (row 3) == 0
    };
    try expectError(MatrixError.MatrixIsNotInvertible, matInverse(&sing));

    sing = .{
        .{ -4,  2, -2,  0 },    // (col 3) == 0
        .{  9,  8,  7,  0 },
        .{  5,  4,  3,  0 },
        .{ 10,  8,  5,  0 },
    };
    try expectError(MatrixError.MatrixIsNotInvertible, matInverse(&sing));
}
