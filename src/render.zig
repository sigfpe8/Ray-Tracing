const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const can = @import("canvas.zig");
const Canvas = can.Canvas;

const mth = @import("math.zig");
const Float = mth.Float;
const Matrix = mth.Matrix;
const Vector = mth.Vector;
const Point = mth.Point;
const point = mth.point;
const vector = mth.vector;
const dot = mth.dot;
const vecMag = mth.vecMag;
const vecUnit = mth.vecUnit;
const vecScale = mth.vecScale;
const matIdentity = mth.matIdentity;
const matMul = mth.matMul;
const matMulVec = mth.matMulVec;
const matMulLeft = mth.matMulLeft;
const matTranspose = mth.matTranspose;
const EPSILON = mth.EPSILON;
const INFINITY = mth.INFINITY;

const mtl = @import("material.zig");
const Color = mtl.Color;
const black = mtl.black;
const colScale = mtl.colScale;


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

const pat = @import("pattern.zig");
const Pattern = pat.Pattern;
const stripes = pat.stripes;
const checkers = pat.checkers;
const rings = pat.rings;
const gradient = pat.gradient;

const sio = @import("stdio.zig");
const printErr = sio.printErr;

const trf = @import("transform.zig");
const invRotationX = trf.invRotationX;
const invRotationY = trf.invRotationY;
const invRotationZ = trf.invRotationZ;
const invScaling = trf.invScaling;
const invTranslation = trf.invTranslation;

// Maximum number of reflected/refracted rays
const MAX_RAYS = 4;
// Maximum number of ray intersectons per object (e.g. Sphere <= 2 intersections)
const MAX_INTERSECTIONS = obi.MAX_INTERSECTIONS;
// Maximum number of container objects (embedded refrative objects)
const MAX_CONTAINERS = 100;

pub const Intersection = struct {
    ob: *const Object,  // Pointer to the object that intercepted the ray
    ti: Float,            // "Time" of intersection
    u: Float,             // Used by smooth triangles
    v: Float,
};

pub fn sortIntersections(xs: []Intersection) void {
    std.mem.sort(Intersection, xs, {}, struct {
        fn lessThan(_: void, lhs: Intersection, rhs: Intersection) bool {
            return lhs.ti < rhs.ti;
        }
    }.lessThan);                   
}

// Precomputed information at a hit point
// All in world coordinates
const HitInfo = struct {
    obj: *const Object,
    pnt: Point,
    over_pnt: Point,
    under_pnt: Point,
    eyev: Vector,       // Unit
    normalv: Vector,    // Unit
    reflectv: Vector,
    inside: bool,
    n1: Float,
    n2: Float,

    pub fn init(xs: []Intersection, hit: usize, r: Ray) HitInfo {
        // `hit` is the index of the hit intersection
        const obj = xs[hit].ob;
        const pnt = r.positionAt(xs[hit].ti);    // World space
        var normalv = obj.normalAt(pnt, &xs[hit]);
        const eyev = vecUnit(-r.dir);
        var inside: bool = undefined;
        var n1: Float = 1.0;
        var n2: Float = 1.0;

        if (dot(normalv, eyev) < 0) {
            inside = true;
            normalv = -normalv;
        } else {
            inside = false;
        }

        // Use statically allocated array in order to speed things up
        var containers: [MAX_CONTAINERS]*const Object = undefined;
        var count: usize = 0;   // # of objects in containers

        for (xs, 0..) |*x, k| {
            if (k == hit) {         // If this is the hit
                if (count > 0) {    // `containers` is not empty
                    n1 = containers[count - 1].material.refractive_index;
                }
            }

            // Check if this object is already in the containers list
            var i: usize = 0;
            while (i < count) : (i += 1) {
                if (containers[i] == x.ob) {    // Yes, x.ob in `containers`, so remove it
                    var j: usize = i + 1;
                    while (j < count) : (j += 1) {
                        containers[i] = containers[j];
                        i += 1;
                    }
                    count -= 1;
                    break;
                }
            } else {    // No, x.ob not in containers, so append it to the list
                // i == count
                if (count == MAX_CONTAINERS) {
                    @panic("Reached MAX_CONTAINERS in HitInfo");
                }
                containers[count] = x.ob;
                count += 1;
            }

            if (k == hit) {      // If this is the hit
                if (count > 0) {    // `containers` is not empty
                    n2 = containers[count - 1].material.refractive_index;
                }
            }
        }

        return .{
            .obj = obj,
            .pnt = pnt,
            // FIX: why do we have to use 10 * EPSILON instead of just EPSILON to remove the noise (acne)?
            .over_pnt = pnt + vecScale(normalv, 50 * EPSILON),
            .under_pnt = pnt - vecScale(normalv, 50 * EPSILON),
            .eyev = eyev,
            .normalv = normalv,
            .reflectv = reflect(r.dir, normalv),
            .inside = inside,
            .n1 = n1,
            .n2 = n2,
        };
    }
};

/// A Setting is the World + a Camera
pub const Setting = struct {
    world: World,
    camera: Camera,
};

/// The World is a collection of objects and lights that make up the world
pub const World = struct {
    scene: *Object,         // Typically a group with several children
    light: PointLight,      // For now, just 1 light
    allocator: Allocator,

    pub fn init(light: PointLight, allocator: Allocator) World {
        const scene = group(allocator); // Empty group/scene
        return .{
            .scene = scene,
            .light = light,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *World) void {
        self.scene.deinit(self.allocator);
        self.scene = undefined;
    }

    // /// Default world, used only for tests.
    // /// Contains a point light at (-10, 10, -10) and two spheres centered
    // /// at the origin, the inner one with radius 0.5 and the outer one
    // /// with radius 1.
    // pub fn default() !World {
    //     const allocator: Allocator = std.testing.allocator;
    //     const light = PointLight{ .intensity = Color{1, 1, 1},
    //                                           .position = point(-10, 10, -10) };

    //     var s1 = sphere();  // Outer sphere
    //     s1.material.color = Color{0.8, 1.0, 0.6};
    //     s1.material.diffuse = 0.7;
    //     s1.material.specular = 0.2;
    //     const ps1: *Object = try allocator.create(Object);
    //     ps1.* = s1;

    //     var s2 = sphere();  // Inner sphere
    //     s2.itrans = trf.invScaling(0.5, 0.5, 0.5);
    //     const ps2: *Object = try allocator.create(Object);
    //     ps2.* = s2;
    //     var objs = try allocator.alloc(*Object, 2);
    //     objs[0] = s1;
    //     objs[1] = s2;

    //     return .{
    //         .objs = objs,
    //         .light = light,
    //         .allocator = allocator,
    //     };
    // }

    pub fn render(self: *const World, cam: *const Camera, fname: []const u8, io: Io) !void {
        const width = cam.hsize;
        const height = cam.vsize;
        var canvas = try Canvas.init(width,height,self.allocator);
        defer canvas.deinit(self.allocator);
        var pixels = canvas.pixels;
        rayStats = RayStats{};

        printErr("\nRendering {s} ({d}x{d}) in a single thread\n", .{fname,width,height});
        const start = std.Io.Clock.now(.awake, io);

        var y: usize = 0;
        while (y < height) : (y += 1) {
            // if (y % 20 == 0) {
            //     std.debug.print("y={d}\n", .{y});
            // }
            var x: usize = 0;
            while (x < width) : (x += 1) {
                const r = Ray.forPixel(cam, x, y);
                const color = self.colorAt(r, MAX_RAYS);
                // pixels[y][x] = color;
                pixels[y * width + x] = color;
            }
        }

        const end = std.Io.Clock.now(.awake, io);
        const dur = start.durationTo(end);

        try canvas.writePPM(io, fname);  

        var buf: [16]u8 = undefined;
        const mil = std.Io.Duration.toMilliseconds(dur);
        const sec = std.Io.Duration.toSeconds(dur);
        printErr("Rendered {s} pixels in ", .{printWithSeparators(width * height, &buf)});
        if (mil < 1000) {
            printErr("{d} ms\n", .{mil});
        } else {
            printErr("{d} s\n", .{sec});
        }
        printErr("\n", .{});
        printErr("Total # of rays: {s:>10}\n", .{printWithSeparators(rayStats.total, &buf)});
        printErr("Reflected rays:  {s:>10}\n", .{printWithSeparators(rayStats.reflected, &buf)});
        printErr("Refracted rays:  {s:>10}\n", .{printWithSeparators(rayStats.refracted, &buf)});
        printErr("Shadow rays:     {s:>10}\n", .{printWithSeparators(rayStats.shadow, &buf)});
    }

    pub fn addAxes(self: *World) void {
        var xAxis = cylinder(self.allocator, -INFINITY, INFINITY, false);
        mth.matMulLeft(&xAxis.itrans, &invScaling(0.1, 0.1, 0.1));
        mth.matMulLeft(&xAxis.itrans, &invRotationZ(std.math.pi / 2.0));
        xAxis.material.color = Color{1, 0, 0};
        self.scene.addShape(xAxis);


        var yAxis = cylinder(self.allocator, -INFINITY, INFINITY, false);
        mth.matMulLeft(&yAxis.itrans, &invScaling(0.06, 0.06, 0.06));
        yAxis.material.color = Color{0, 1, 0};
        self.scene.addShape(yAxis);

        var zAxis = cylinder(self.allocator, -INFINITY, INFINITY, false);
        mth.matMulLeft(&zAxis.itrans, &invScaling(0.06, 0.06, 0.06));
        mth.matMulLeft(&zAxis.itrans, &invRotationX(std.math.pi / 2.0));
        zAxis.material.color = Color{0, 0, 1};
        self.scene.addShape(zAxis);
    }

    pub fn renderThreads(self: *const World, cam: *const Camera, fname: []const u8, io: Io, nthrds: usize) !void {
        const width = cam.hsize;
        const height = cam.vsize;
        var canvas = try Canvas.init(width,height,self.allocator);
        defer canvas.deinit(self.allocator);
        const pixels = canvas.pixels;
        rayStats = RayStats{};

        printErr("\nRendering {s} ({d}x{d}) with {d} threads\n", .{fname,width,height,nthrds});
        var grp: std.Io.Group = .init;

        const thrdHeight: usize = @divTrunc(height,nthrds);
        const start = std.Io.Clock.now(.awake, io);

        // Spawn nthrds threads
        // Each thread will handle thrdHeight lines, except maybe the
        // last one, which will handle up to (2 * thrdHeight - 1) when
        // nthrds does not divide height exactly.
        var len = thrdHeight;
        var y: usize = 0;
        while (y < height) : (y += len) {
            len = if (height - y < 2 * thrdHeight) height - y else thrdHeight;
            // std.debug.print("y={d}, len={d}\n", .{y,len});
            try grp.concurrent(io, renderThread, .{ self, cam, y, len, pixels });
        }

        // Wait for all threads to finish
        // std.debug.print("Waiting for threads to finish\n",.{});
        try grp.await(io);

        const end = std.Io.Clock.now(.awake, io);
        const dur = start.durationTo(end);

        try canvas.writePPM(io, fname);  

        var buf: [16]u8 = undefined;
        const mil = std.Io.Duration.toMilliseconds(dur);
        const sec = std.Io.Duration.toSeconds(dur);
        printErr("Rendered {s} pixels in ", .{printWithSeparators(width * height, &buf)});
        if (mil < 1000) {
            printErr("{d} ms\n", .{mil});
        } else {
            printErr("{d} s\n", .{sec});
        }
        printErr("\n", .{});
        printErr("Total # of rays: {s:>10}\n", .{printWithSeparators(rayStats.total, &buf)});
        printErr("Reflected rays:  {s:>10}\n", .{printWithSeparators(rayStats.reflected, &buf)});
        printErr("Refracted rays:  {s:>10}\n", .{printWithSeparators(rayStats.refracted, &buf)});
        printErr("Shadow rays:     {s:>10}\n", .{printWithSeparators(rayStats.shadow, &buf)});
    }

    // Thread function to handle a block of contiguous lines
    fn renderThread(self: *const World,
                    cam: *const Camera,
                    yIni: usize,
                    len: usize,
                    pixels: []Color) std.Io.Cancelable!void {
        var y: usize = yIni;
        const width = cam.hsize;
        const height = yIni + len;

        while (y < height) : (y += 1) {
            var x: usize = 0;
            while (x < width) : (x += 1) {
                const r = Ray.forPixel(cam, x, y);
                const color = self.colorAt(r, MAX_RAYS);
                pixels[y * width + x] = color;
            }
        }
    }

    pub fn colorAt(self: *const World, r: Ray, rays: isize) Color {
        var xs: [MAX_INTERSECTIONS]Intersection = undefined;
        var color = black;
    
        const count = self.scene.intersects(r, &xs);

        if (hitIndex(xs[0..count])) |i| {
            const hi = HitInfo.init(xs[0..count], i, r);
            color = self.shadeHit(&hi, rays);
        }

        return color;
    }

    pub fn shadeHit(self: *const World, hi: *const HitInfo, rays: isize) Color {
        const shadowed = self.isShadowed(hi.over_pnt);
        const surface = self.lighting(hi, shadowed);
        const reflected = self.refletedColor(hi, rays);
        const refracted = self.refractedColor(hi, rays);
        return surface + reflected + refracted;
    }

    pub fn isShadowed(self: *const World, pnt: Point) bool {
        var xs: [MAX_INTERSECTIONS]Intersection = undefined;
        const dir = self.light.position - pnt;
        const dist_to_light = vecMag(dir);
        // dir = vecUnit(dir);
        const r = Ray.unit(pnt, dir);
        rayStats.shadow += 1;
        const count = self.scene.intersects(r, &xs);

        if (hitIndex(xs[0..count])) |i| {
            return xs[i].ti < dist_to_light;
        }

        // No objects between this point and the light source
        return false;
    }

    pub fn lighting(self: *const World, hi: *const HitInfo, in_shadow: bool) Color {
        const light = &self.light;
        const material = &hi.obj.material;
        const normalv = hi.normalv;
        const eyev = hi.eyev;
        const pnt = hi.over_pnt;
        
        const base_color = if (material.pattern.active) material.pattern.colorAt(pnt) else material.color;
        // Combine the surface color with the light's color/intensity
        const effective_color = base_color * light.intensity;
        // Compute the ambient contribution
        const ambient = colScale(effective_color, material.ambient);
        if (in_shadow) {    // Ignore diffuse and specular
            return ambient;
        }

        // Find the direction to the light source
        const lightv = vecUnit(light.position - pnt);
        // light_dot_normal represents the cosine of the angle between the
        // light vector and the normal vector. A negative number means the
        // light is on the other side of the surface.
        const light_dot_normal = dot(lightv, normalv);
        var diffuse: Color = undefined;
        var specular: Color = undefined;
        if (light_dot_normal < 0) {
            diffuse = black;
            specular = black;
        } else {
            // Compute the diffuse contribution
            diffuse = colScale(effective_color, material.diffuse * light_dot_normal);

            // reflect_dot_eye represents the cosine of the angle between the
            // reflection vector and the eye vecto. A negative number means the
            // light reflects away from the eye.
            const reflectv = reflect(-lightv, normalv);
            const reflect_dot_eye = dot(reflectv, eyev);

            if (reflect_dot_eye <= 0) {
                specular = black;
            } else {
                // Compute the specular contribution
                const factor: Float = std.math.pow(Float, reflect_dot_eye, material.shininess);
                specular = colScale(light.intensity, material.specular * factor);
            }
        }
        return ambient + diffuse + specular;
    }

    pub fn refletedColor(self: *const World, hi: *const HitInfo, rays: isize) Color {
        if (rays <= 0 or hi.obj.material.reflective == 0) {
            return black;
        }

        const reflect_ray = Ray.new(hi.over_pnt, hi.reflectv);
        rayStats.reflected += 1;
        const color = self.colorAt(reflect_ray, rays - 1);
        return colScale(color, hi.obj.material.reflective);
    }

    pub fn refractedColor(self: *const World,hi: *const HitInfo, rays: isize) Color {
        if (rays <= 0 or hi.obj.material.transparency == 0) {
            return black;
        }

        // Find the ratio of the first index of refraction to the second
        const n_ratio = hi.n1 / hi.n2;
        // cos(theta_i) = dot product of normal and incident (eye) vectors (both unit)
        const cos_i = dot(hi.eyev, hi.normalv);

        // Find sin(theta_i)^2 via trigonometry
        const sin2_t = n_ratio * n_ratio * (1.0 - cos_i * cos_i);

        // std.debug.print("n1={d}, n2={d}, sin2_t={d}\n", .{hi.n1, hi.n2, sin2_t});
        // If sin2_t > 1 then there is total internal reflection
        if (sin2_t > 1) {
            return black;
        }

        // Find cos(theta_t)
        const cos_t = @sqrt(1.0 - sin2_t);

        // Create the refracted ray
        const dir = vecScale(hi.normalv, n_ratio * cos_i - cos_t) - vecScale(hi.eyev, n_ratio);
        const refract_ray = Ray.new(hi.under_pnt, vecUnit(dir));
        rayStats.refracted += 1;
        const color = self.colorAt(refract_ray, rays - 1);

        return colScale(color, hi.obj.material.transparency);
    }
};

pub const RayStats = struct {
    total: usize = 0,
    reflected: usize = 0,
    refracted: usize = 0,
    shadow: usize = 0,
};

pub var rayStats: RayStats = undefined;

pub const Ray = struct {
    ori: Point,
    dir: Vector,

    /// Create a ray with arbitrary length
    pub fn new(ori: Point, dir: Vector) Ray {
        rayStats.total += 1;
        return .{
            .ori = ori,
            .dir = dir,
        };
    }

    /// Create a ray with unit length
    pub fn unit(ori: Point, dir: Vector) Ray {
        rayStats.total += 1;
        return .{
            .ori = ori,
            .dir = vecUnit(dir),
        };
    }

    pub fn positionAt(self: *const Ray, t: Float) Point {
        // o + t * d
        return self.ori + vecScale(self.dir, t);
    }

    /// Apply a transformation to a ray. The resulting ray may
    /// not be unit length and this is expected.
    pub fn transform(self: *const Ray, mat: *const Matrix) Ray {
        const ori = matMulVec(mat, self.ori);
        const dir = matMulVec(mat, self.dir);
        return .{
            .ori = ori,
            .dir = dir,
        };
    }

    pub fn forPixel(cam: *const Camera, px: usize, py: usize) Ray {
        // The offset from the edge of the canvas to the pixel's center
        const xoff: Float = (@as(Float,@floatFromInt(px)) + 0.5) * cam.pixel_size;
        const yoff: Float = (@as(Float,@floatFromInt(py)) + 0.5) * cam.pixel_size;

        // The untransformed coordinates of the pixel in world space.
        // (remember that the camera looks toward -z, so +x is to the *left*)
        const world_x = cam.half_width - xoff;
        const world_y = cam.half_height - yoff;

        // Using the camera matrix, transform the canvas point and the origin,
        // and then compute the ray's direction vector.
        // (remember that the canvas is at z = -1)
        const pixel = matMulVec(&cam.itrans, point(world_x, world_y, -1));
        const origin = matMulVec(&cam.itrans, point(0, 0, 0));
        const direction = vecUnit(pixel - origin);
        rayStats.total += 1;

        return .{ .ori = origin, .dir = direction };
    }
};

// The canvas is always 1 unit in front of the camera
pub const Camera = struct {
    hsize: usize,       // Horizontal size of the canvas in pixels
    vsize: usize,       // Vertical size of the canvas in pixels
    fov: Float,         // Field of view (angle in radians)
    pixel_size: Float,  // Pixel size in world units
    half_width: Float,
    half_height: Float,
    itrans: Matrix,     // Inverse view transformation

    pub fn init(hs: usize, vs: usize, fv: Float, from: Point, to: Point, up: Vector) Camera {
        const half_view = @tan(fv / 2);
        const aspect: Float = @as(Float,@floatFromInt(hs)) / @as(Float,@floatFromInt(vs));
        var half_width: Float = undefined;
        var half_height: Float = undefined;

        if (aspect < 1) {
            // Portrait canvas (taller than wider)
            half_width = half_view;
            half_height = half_view / aspect;
        } else {
            // Landscape or square canvas (wider than taller or square)
            half_width = half_view * aspect;
            half_height = half_view;
        }

        const view: Matrix = trf.viewTransform(from, to, up);
        const itrans = mth.matInverse(&view) catch {
            @panic("Non-invertible view matrix in Camera.init()");
        };

        return .{
            .hsize = hs,
            .vsize = vs,
            .fov = fv,
            .pixel_size = (half_width * 2) / @as(Float,@floatFromInt(hs)),
            .half_width = half_width,
            .half_height = half_height,
            .itrans = itrans,
        };
    }
};

pub const PointLight = struct {
    intensity: Color,
    position: Point,
};

/// Return the index of the closest nonnegative intersection.
/// The input slice is sorted by time, so we can stop at the first
/// nonnegative one. Return `null` if none found.
fn hitIndex(xs: []Intersection) ?usize {
    for (xs, 0..) |x, i| {
        if (x.ti >= 0) {
            return i;
        }
    }
    return null;
}

/// Given an incident vector and a normal at a hit point,
/// return the reflected vector at that point
fn reflect(v: Vector, n: Vector) Vector {
    // v - 2(v . n) n
    // The minus sign here is because v is incident, and
    // therefore (v.n) is negative.
    return v - mth.vecScale(n, 2 * dot(v,n));
}

/// Print a non-negative integer separating groups of 3 digits
/// with a delimiter for better human readalbility. For simplicity,
/// truncate the number if the buffer is not big enough.
pub fn printWithSeparators(num: usize, buf: []u8) []u8 {
    // const sep = '_';
    const sep = ',';
    var n = num;
    var i: usize = 0;
    var l: usize = 0;

    // Generate digits in reverse
    while (i < buf.len - 1) {   // Leave room for a digit and a separator
        const d: u8 = @truncate(n % 10);
        n /= 10;
        buf[i] = d + '0';
        i += 1;
        l += 1;
        if (n == 0) {
            break;
        }
        if (l == 3) {   // Time to add a separator
            buf[i] = sep;
            i += 1;
            l = 0;
        }
    }

    // Now put the digits back in the right order
    std.mem.reverse(u8, buf[0..i]);

    return buf[0..i];
}

const expect = std.testing.expect;
const expectApproxEq = std.testing.expectApproxEqAbs;

test "printWithSeparators" {
    var buf: [16]u8 = undefined;
    var b: []u8 = undefined;

    b = printWithSeparators(0, &buf);
    try expect(std.mem.eql(u8, b, "0"));

    b = printWithSeparators(12, &buf);
    try expect(std.mem.eql(u8, b, "12"));

    b = printWithSeparators(123, &buf);
    try expect(std.mem.eql(u8, b, "123"));

     b = printWithSeparators(1234, &buf);
    try expect(std.mem.eql(u8, b, "1,234"));

     b = printWithSeparators(123456, &buf);
    try expect(std.mem.eql(u8, b, "123,456"));

    b = printWithSeparators(1234567890, &buf);
    try expect(std.mem.eql(u8, b, "1,234,567,890"));
}

test "Objects" {
    const allocator = std.testing.allocator;
    var xs: [2]Intersection = undefined;

    var r = Ray.new(point(0,0,-5), vector(0,0,1));
    const s = sphere(allocator);
    defer s.deinit(allocator);
    var count = s.intersects(r, &xs);

    try expect(count == 2);
    try expectApproxEq(xs[0].ti, 4.0, EPSILON);
    try expectApproxEq(xs[1].ti, 6.0, EPSILON);

    r = Ray.new(point(0,1,-5), vector(0,0,1));
    count = s.intersects(r, &xs);
    try expect(count == 2);
    try expectApproxEq(xs[0].ti, 5.0, EPSILON);
    try expectApproxEq(xs[1].ti, 5.0, EPSILON);

    r = Ray.new(point(0,10,-5), vector(0,0,1));
    count = s.intersects(r, &xs);
    try expect(count == 0);
}

test "sortIntersections" {
    const allocator = std.testing.allocator;
    var xs: [3]Intersection = undefined;

    const o0 = sphere(allocator);
    defer o0.deinit(allocator);
    xs[0] = .{
        .ob=o0,
        .ti = 3,
        .u = 3,
        .v = 3 };

    const o1 = sphere(allocator);
    defer o1.deinit(allocator);
    xs[1] = .{
        .ob=o1,
        .ti = -1,
        .u = -1,
        .v = -1 };

    const o2 = sphere(allocator);
    defer o2.deinit(allocator);
    xs[2] = .{
        .ob=o2,
        .ti = 2,
        .u = 2,
        .v = 2 };

    sortIntersections(&xs);

    try expect(xs[0].ti == -1);
    try expect(xs[0].ob == o1);

    try expect(xs[1].ti == 2);
    try expect(xs[1].ob == o2);

    try expect(xs[2].ti == 3);
    try expect(xs[2].ob == o0);
}



// test "makeCSG" {
//     const allocator = std.testing.allocator;
//     const io = std.testing.io;
//     try makeCSG(io, allocator);
// }