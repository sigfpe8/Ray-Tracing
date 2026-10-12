const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Reader = Io.Reader;
const Writer = Io.Writer;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;


pub const EPSILON = 0.00001;


pub const ArrayError = error{
    IncompatibleDimensions,
};

pub fn Vector(comptime T: type, comptime N: usize) type {
    return struct {
        elems: [N]T,

        const Self = @This();

        pub fn zeros(self: *Self) void {
            @memset(self.elems, 0);
        }

        pub fn add(self: *Self, other: *Self) !T {
            var res: [N]T = .{};
            var i: usize = 0;
            while (i < N) : (i += 1) {
                res[i] = self.elems[i] + other.elems[i];
            }

            return res;
        }

        pub fn sub(self: *Self, other: *Self) !T {
            var res: [N]T = .{};
            var i: usize = 0;
            while (i < N) : (i += 1) {
                res[i] = self.elems[i] - other.elems[i];
            }

            return res;
        }

        pub fn mul(self: *Self, other: *Self) !T {
            var res: [N]T = .{};
            var i: usize = 0;
            while (i < N) : (i += 1) {
                res[i] = self.elems[i] * other.elems[i];
            }

            return res;
        }

        pub fn dot(self: *Self, other: *Self) !T {
            var res: T = 0;
            var i: usize = 0;
            while (i < N) : (i += 1) {
                res += self.elems[i] * other.elems[i];
            }

            return res;
        }
    };
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


/// Matrices
pub fn Matrix(comptime T: type) type {
    return struct {
        rows: usize,
        cols: usize,
        elems: []T,

        const Self = @This();

        /// Create m-by-n matrix with zeros
        pub fn init(m: usize, n: usize, allocator: Allocator) !Self {
            const nelems = m * n;
            const elems = try allocator.alloc(T, nelems);

            // Clear the matrix
            @memset(elems, 0);

            return .{
                .rows = m,
                .cols = n,
                .elems = elems,
            };
        }

        /// Free matrix elements
        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.elems);
        }

        /// Create n-by-n identity (square) matrix
        pub fn ident(n: usize, allocator: Allocator) !Self {
            const nelems = n * n;
            const elems = try allocator.alloc(T, nelems);

            // Clear the matrix
            @memset(elems, 0);

            // Initialize diagonal with 1's
            var index: usize = 0;
            while (index < nelems) : (index += n + 1) {
                elems[index] = 1.0;
            }

            return .{
                .rows = n,
                .cols = n,
                .elems = elems,
            };
        }

        pub fn get(self: *Self, r: usize, c: usize) T {
            assert(r < self.rows);
            assert(c < self.cols);
            const index = r * self.cols + c;
            return self.elems[index];
        }

        pub fn set(self: *Self, v: T, r: usize, c: usize) void {
            assert(r < self.rows);
            assert(c < self.cols);
            const index = r * self.cols + c;
            self.elems[index] = v;
        }

        pub fn print(self: *const Self, w: *Writer) !void {
            var r: usize = 0;
            while (r < self.rows) : (r += 1) {
                var c: usize = 0;
                while (c < self.cols) : (c += 1) {
                    const index = r * self.cols + c;
                    switch (@typeInfo(T)) {
                        .float => try w.print("{d: >6.2} ", .{self.elems[index]}),
                        .int =>  try w.print("{d} ", .{self.elems[index]}),
                        // FIX: The following prints a + sign in front of all the elements. Why?
                        // .int =>  try w.print("{d: >6} ", .{self.elems[index]}),
                        else => unreachable,
                    }
                }
                try w.print("\n", .{});
            }
            try w.flush();
        }

        /// Checks if two matrices are equal
        pub fn equal(self: *const Self, other: *const Self) bool {
            // Must have same dimensions
            if (self.rows != other.rows or self.cols != other.cols) {
                return false;
            }
            const n = self.rows * self.cols;
            var i: usize = 0;
            while (i < n) : (i += 1) {
                const a = self.elems[i];
                const b = other.elems[i];
                switch (@typeInfo(T)) {
                    // Exact equality for integers
                    .int => {
                        if (a != b) {
                            return false;
                        }
                    },
                    // Equality within tolerance for floating points
                    .float => {
                        if (!std.math.approxEqAbs(T, a, b, EPSILON)) {
                            std.debug.print("a={d}, b={d}, i={d}\n", .{a,b,i});
                            return false;
                        }
                    },
                    else => unreachable,
                }
            }
            return true;
        }
    };
}
