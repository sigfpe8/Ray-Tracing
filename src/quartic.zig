//  Utility functions to find cubic and quartic roots,
//  coefficients are passed like this:
//
//      c[0] + c[1]*x + c[2]*x^2 + c[3]*x^3 + c[4]*x^4 = 0
//
//  The functions return the number of non-complex roots and
//  put the values into the s array.
//
//  Author of original C code:  Jochen Schwarze (schwarze@isa.de)
//
// https://github.com/erich666/GraphicsGems/blob/master/gems/Roots3And4.c

const std = @import("std");
const mth = @import("math.zig");
const Float = mth.Float;

const acos = std.math.acos;
const cbrt = std.math.cbrt;
const pi = std.math.pi;

// epsilon surrounding for near zero values
const EQN_EPS: Float = 1e-6;
// When Float = f32, EQN_EPS = 1e-7
//            = f64, EQL_EPQ = 1e-9

inline fn isZero(x: Float) bool {
    return (x > -EQN_EPS and x < EQN_EPS);
}


pub fn solveQuadric(c: []const Float, s: []Float) usize {
    // Normal form: x^2 + px + q = 0
    const p = c[ 1 ] / (2 * c[ 2 ]);
    const q = c[ 0 ] / c[ 2 ];

    const D = p * p - q;

    if (isZero(D)) {
        s[ 0 ] = -p;
        return 1;
    } else if (D < 0) {
        return 0;
    } else { // if (D > 0)
        const sqrt_D = @sqrt(D);

        s[ 0 ] =  sqrt_D - p;
        s[ 1 ] = -sqrt_D - p;
        return 2;
    }
}


pub fn solveCubic(c: []const Float, s: []Float) usize {
    // Normal form: x^3 + Ax^2 + Bx + C = 0
    const A = c[ 2 ] / c[ 3 ];
    const B = c[ 1 ] / c[ 3 ];
    const C = c[ 0 ] / c[ 3 ];

    // substitute x = y - A/3 to eliminate quadric term:
	//     x^3 +px + q = 0 */

    const sq_A = A * A;
    const p = (1.0/3.0) * ((-1.0/3.0) * sq_A + B);
    const q = (1.0/2.0) * ((2.0/27.0) * A * sq_A - (1.0/3.0) * A * B + C);

    // Use Cardano's formula

    const cb_p = p * p * p;
    const D = q * q + cb_p;

    var num: usize = undefined; // Number of real solutions

    if (isZero(D)) {
	    if (isZero(q)) {// one triple solution
            s[ 0 ] = 0;
            num = 1;
    	} else { // one single and one double solution
            const u = cbrt(-q);
            s[ 0 ] = 2 * u;
            s[ 1 ] = -u;
            num = 2;
        }
    } else if (D < 0) { // Casus irreducibilis: three real solutions
        const phi = (1.0/3.0) * acos(-q / @sqrt(-cb_p));
        const t = 2 * @sqrt(-p);

        s[ 0 ] =  t * @cos(phi);
        s[ 1 ] = -t * @cos(phi + pi / 3.0);
        s[ 2 ] = -t * @cos(phi - pi / 3.0);
        num = 3;
    } else { // one real solution
        const sqrt_D = @sqrt(D);
        const u = cbrt(sqrt_D - q);
        const v = -cbrt(sqrt_D + q);

        s[ 0 ] = u + v;
        num = 1;
    }

    // resubstitute

    const sub = (1.0/3.0) * A;

    var i: usize = 0;
    while (i < num) : (i += 1) {
    	s[ i ] -= sub;
    }

    return num;
}

pub fn solveQuartic(c: []const Float, s: []Float) usize {
    var coeffs: [4]Float = undefined;

    // normal form: x^4 + Ax^3 + Bx^2 + Cx + D = 0
    const A = c[ 3 ] / c[ 4 ];
    const B = c[ 2 ] / c[ 4 ];
    const C = c[ 1 ] / c[ 4 ];
    const D = c[ 0 ] / c[ 4 ];

    //  substitute x = y - A/4 to eliminate cubic term:
	//     x^4 + px^2 + qx + r = 0 */

    const sq_A = A * A;
    const p = (-3.0/8.0) * sq_A + B;
    const q = (1.0/8.0) * sq_A * A - (1.0/2.0) * A * B + C;
    const r = (-3.0/256.0)*sq_A*sq_A + (1.0/16.0)*sq_A*B - (1.0/4.0)*A*C + D;

    var num: usize = undefined;

    if (isZero(r)) {
	    // no absolute term: y(y^3 + py + q) = 0
        coeffs[ 0 ] = q;
        coeffs[ 1 ] = p;
        coeffs[ 2 ] = 0;
        coeffs[ 3 ] = 1;

    	num = solveCubic(&coeffs, s);

	    s[ num ] = 0;
        num += 1;
    } else {
        // Solve the resolvent cubic ...
        coeffs[ 0 ] = (1.0/2.0) * r * p - (1.0/8.0) * q * q;
        coeffs[ 1 ] = -r;
        coeffs[ 2 ] = (-1.0/2.0) * p;
        coeffs[ 3 ] = 1;

	    _ = solveCubic(&coeffs, s);

        // ... and take the one real solution ...

	    const z = s[ 0 ];

	    // ... to build two quadric equations

	    var u = z * z - r;
	    var v = 2 * z - p;

        if (isZero(u)) {
            u = 0;
        } else if (u > 0) {
            u = @sqrt(u);
        } else {
            return 0;
        }

        if (isZero(v)) {
            v = 0;
        } else if (v > 0) {
            v = @sqrt(v);
        } else {
            return 0;
        }

        coeffs[ 0 ] = z - u;
        coeffs[ 1 ] = if (q < 0) -v else v;
        coeffs[ 2 ] = 1;

        num = solveQuadric(&coeffs, s);

        coeffs[ 0 ]= z + u;
        coeffs[ 1 ] = if (q < 0) v else -v;
        coeffs[ 2 ] = 1;

        num += solveQuadric(&coeffs, s[num..]);
    }

    // Resubstitute
    const sub = (1.0/4.0) * A;

    var i: usize = 0;
    while (i < num) : (i += 1) {
	    s[ i ] -= sub;
    }

    // Sort the roots
    // TODO: see if we can simplify this sort by using a Sorting Network
    if (num > 1) {
        if (num == 2) {
            if (s[1] < s[0]) {
                const t = s[0];
                s[0] = s[1];
                s[1] = t;
            }
        } else {
            std.mem.sort(Float, s[0..num], {}, struct {
                    fn lessThan(_: void, lhs: Float, rhs: Float) bool {
                        return lhs < rhs;
                    }
                }.lessThan);                   
        }
    }

    return num;
}

const expect = std.testing.expect;

test "solveCubic" {
    // Example: x^3 - 21x^2 + 146x - 336 = 0
    // Roots: 6, 7, 8
    var coeffs = [_]Float{ -336, 146, -21, 1 };
    var sols: [3]Float = undefined;

    const n = solveCubic(&coeffs, &sols);
    try expect(n == 3);

    std.debug.print("Cubic: found {d} real solutions:\n", .{n});
    var i: usize = 0;
    while (i < n) : (i += 1) {
        std.debug.print("  [{d}] -> {d:.6}\n", .{i, sols[i]});
    }
}

test "solveQuartic" {
    // Example: x^4 - 10x^3 + 35x^2 - 50x + 24 = 0
    // Roots: 1, 2, 3, 4
    var coeffs = [_]Float{ 24, -50, 35, -10, 1 };
    var sols: [4]Float = undefined;

    const n = solveQuartic(&coeffs, &sols);
    // try expect(n == 4);

    std.debug.print("Quartic: found {d} real solutions:\n", .{n});
    var i: usize = 0;
    while (i < n) : (i += 1) {
        std.debug.print("  [{d}] -> {d:.6}\n", .{i, sols[i]});
    }
}