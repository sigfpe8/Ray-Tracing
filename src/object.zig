//! Geometric objects that can be rendered, like spheres, planes and triangles
const std = @import("std");
const Allocator = std.mem.Allocator;
const approxEqAbs = std.math.approxEqAbs;

const bvh = @import("bvh.zig");
const BBox = bvh.BBox;
const bbox = bvh.bbox;

const mth = @import("math.zig");
const Float = mth.Float;
const Matrix = mth.Matrix;
const Point = mth.Point;
const Vector = mth.Vector;
const point = mth.point;
const vector = mth.vector;
const dot = mth.dot;
const cross = mth.cross;
const vecMag = mth.vecMag;
const vecUnit = mth.vecUnit;
const vecScale = mth.vecScale;
const matIdentity = mth.matIdentity;
const matInverse = mth.matInverse;
const matMulVec = mth.matMulVec;
const matMulLeft = mth.matMulLeft;
const matTranspose = mth.matTranspose;
const EPSILON = mth.EPSILON;
const INFINITY = mth.INFINITY;

const mtl = @import("material.zig");
const Material = mtl.Material;

const rnd = @import("render.zig");
const Ray = rnd.Ray;
const Intersection = rnd.Intersection;
const sortIntersections = rnd.sortIntersections;

const trf = @import("transform.zig");
const invRotationX = trf.invRotationX;
const invRotationY = trf.invRotationY;
const invRotationZ = trf.invRotationZ;
const invScaling = trf.invScaling;
const invTranslation = trf.invTranslation;

// Maximum number of ray intersectons per object
// Sphere <= 2 intersections
// Torus  <= 4 intersections
pub const OBJ_INTERSECTIONS = 4;
// Size of static xs[] arrays
pub const MAX_INTERSECTIONS = OBJ_INTERSECTIONS * 10;

pub const ObjType = enum {
    objCone,
    objCube,
    objCylinder,
    objPlane,
    objSphere,
};

/// This is the interface that all object types must implement.
/// These functions perform operations in the *object* space.
/// All transformations between world and object space are performed by the
/// upper level functions of the same name that call them via the VTable.
const VTable = struct {
    intersects: *const fn (self: *const Object, r: Ray, xs: []Intersection) usize,
    normalAt: *const fn (self: *const Object, obj_point: Point, *const Intersection) Vector,
    includes: *const fn (self: *const Object, other: *const Object) bool,
    addShape: *const fn (self: *Object, shape: *Object) void,
    boundsOf: *const fn (self: *const Object) BBox,
    clone: *const fn (self: *const Object, newobj: *Object, allocator: Allocator) void,
    deinit: *const fn (self: *Object, allocator: Allocator) void,
};

pub const Object = struct {
    parent: ?*const Object = null,   // Pointer to parent, if any
    data: ?*anyopaque = null, // Payload for some object types (e.g. Cylinder/Group/CSG)
    vtable: *const VTable,    // Pointer to interface
    itrans: Matrix,           // Inverse transformation for the ray
    material: Material,       // Object material properties

    const Self = @This();

    /// Return a pointer to a dynamically allocated Object with the given VTable
    pub fn init(allocator: Allocator, vtable: *const VTable) *Object {
        const obj = allocator.create(Object) catch {
            @panic("Out of memory in Object.init()");
        };

        obj.* = .{
            .vtable = vtable,
            .itrans = matIdentity(),
            .material = Material{},
        };

        return obj;
    }

    // Free an object and its descendants
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.data != null) {
            self.vtable.deinit(self, allocator);
            self.data = null;
        }
        allocator.destroy(self);
    }

    /// Return the bounding box of a shape
    pub fn boundsOf(self: *const Self) BBox {
        return self.vtable.boundsOf(self);
    }

    /// Return the bbox of a shape modified by its direct transformation
    pub fn parentSpaceBoundsOf(self: *const Self) BBox {
        const box = self.vtable.boundsOf(self);
        const mat = matInverse(&self.itrans) catch {
            @panic("Non-invertible matrix in Object.parentSpaceBoundsOf()");
        };
        const tbox = box.transform(&mat);
        return tbox;
    }
    
    /// Duplicate an object and its descendants
    pub fn clone(self: *const Self, allocator: Allocator) *Object {
        const newobj = allocator.create(Object) catch {
            @panic("Out of memory in Object.clone()");
        };

        // newobj.* = *self;   // .parent is set by group/csgClone()
        newobj.parent = null;
        newobj.vtable = self.vtable;
        newobj.itrans = self.itrans;
        newobj.material = self.material;
        if (self.data != null) {
            self.vtable.clone(self, newobj, allocator);
        } else {
            newobj.data = null;
        }

        return newobj;
    }

    /// Return the number of intersections of the ray with the object.
    /// If there are intersections, fill in the corresponding nodes in xs[].
    pub fn intersects(self: *const Self, r: Ray, xs: []Intersection) usize {
        // Transform the ray from world to object space using 
        // the object's inverse transformation
        const rt = r.transform(&self.itrans);
        return self.vtable.intersects(self, rt, xs);
    }

    pub fn normalAt(self: *const Self, world_point: Point, px: *const Intersection) Vector {
        // Convert point to object coordinates
        const obj_point = self.worldToObject(world_point);
        // Determine the normal in the object space
        const obj_normal: Vector = self.vtable.normalAt(self, obj_point, px);
        // Convert normal to world coordinates
        return self.normalToWorld(obj_normal);
    }

    pub fn includes(self: *const Self, other: *const Object) bool {
        return self.vtable.includes(self, other);
    }

    pub fn addShape(self: *Self, shape: *Object) void {
        return self.vtable.addShape(self, shape);
    }

    pub fn normalToWorld(self: *const Self, obj_normal: Vector) Vector {
        const transp = matTranspose(&self.itrans);
        var world_normal = matMulVec(&transp, obj_normal);
        world_normal[3] = 0;
        world_normal = vecUnit(world_normal);

        if (self.parent) |obj| {
            world_normal = obj.normalToWorld(world_normal);
        }

        return world_normal;
    }

    pub fn worldToObject(self: *const Self, world_point: Point) Point {
        var obj_point = world_point;
        if (self.parent) |obj| {
            obj_point = obj.worldToObject(obj_point);
        }

        obj_point = matMulVec(&self.itrans, obj_point);
        return obj_point;
    }

    /// Chain inverse transformations. Each new transformation
    /// is multiplied on the right, so the last one that was
    /// chained is the first one to take effect.
    pub fn chainTransf(self: *Self, trans: *const Matrix) void {
        mth.matMulLeft(&self.itrans, trans);
    }
};

fn errorDeinit(self: *Object, allocator: Allocator) void {
    _ = self;
    _ = allocator;
    @panic("Simple shapes should not call deinit()");
}

fn errorNormalAt(self: *const Object, world_point: Point, px: *const Intersection) Vector {
    _ = self;
    _ = world_point;
    _ = px;
    @panic("Only simple shapes should call normalAt()");
}

fn errorAddShape(self: *Object, shape: *Object) void {
    _ = self;
    _ = shape;
    @panic("Can only add shapes to groups!");
}

fn errorClone(self: *const Object, newobj: *Object, allocator: Allocator) void {
    _ = self;
    _ = newobj;
    _ = allocator;
    @panic("Clone function not implemented yet");
}

// Group pseudo-object --------------------------------------------------------

/// A Group is a container for objects (simple objects like spheres and cubes and
/// composite objects like csgs and groups). It carries its own allocator because
/// groupIntersects() needs an allocator to expand the list of intersections
/// and it would be awkward to pass it to all the xxxIntersects() methods when
/// only the one for groups needs it. This is one of those cases where Zig's blind
/// adherence to certain principles (all functions that allocate memory should
/// be passed an allocator in order to make it very clear that memory is being
/// allocated) hinders more than helps. I'm tempted to make the allocator a
/// global variable in object.zig and render.zig.
pub const Group = struct {
    allocator: Allocator,           // It would be nicer to have a default allocator
    objects: std.ArrayList(*Object),// List of contained objects

    // Return a pointer to a dynamically allocated empty Group
    pub fn init(allocator: Allocator) *Group {
        const grp = allocator.create(Group) catch {
            @panic("Out of memory in Group.init()");
        };

        grp.allocator = allocator;
        grp.objects = .empty;

        return grp;
    }

    pub fn deinit(self: *Group) void {
        const allocator = self.allocator;
        // Release objects contained by this group
        for (self.objects.items) |obj| {
            obj.deinit(allocator);
        }
        // Release the objects list itself
        self.objects.deinit(allocator);

        // Release the group itself
        allocator.destroy(self);
    }
};

pub fn group(allocator: Allocator) *Object {
    var obj = Object.init(allocator, &group_vtable);
    const grp = Group.init(allocator);
    obj.data = grp;

    return obj;
}

var group_vtable = VTable {
    .intersects = groupIntersects,
    .normalAt = errorNormalAt,
    .includes = groupIncludes,
    .addShape = groupAddShape,
    .boundsOf = groupBoundsOf,
    .clone = groupClone,
    .deinit = groupDeinit,
};

/// Out-of-memory errors are fatal, no need to send them up the call chain.
fn groupIntersects(self: *const Object, r: Ray, xs: []Intersection) usize {
    const payload = self.data.?;
    const grp: *Group = @ptrCast(@alignCast(payload));
    const allocator = grp.allocator;
    var list: std.ArrayList(Intersection) = .empty;
    defer list.deinit(allocator);

    // Scan all objects and subgroups recursively
    var xs_temp: [MAX_INTERSECTIONS]Intersection = undefined;

    // Scan all objects in this group
    for (grp.objects.items) |obj| {
        const count = obj.intersects(r, &xs_temp);
        if (count > 0) {
            list.appendSlice(allocator, xs_temp[0..count]) catch {
                @panic("Out of memory in groupIntersects()");
            };
        }
    }

    const count = list.items.len;

    // If there was more than 1 intersection, sort the array by time
    if (count > 1) {
        sortIntersections(list.items);
    }

    // Must have room for all intersections
    if (xs.len < count) {
        @panic("Not enough xs[] slots in groupIntersects()");
    }

    // Copy intersections from list to xs[]
    std.mem.copyForwards(Intersection, xs, list.items);

    return count;
}

fn groupIncludes(self: *const Object, other: *const Object) bool {
    const payload = self.data.?;
    const grp: *Group = @ptrCast(@alignCast(payload));

    for (grp.objects.items) |obj| {
        if (obj.includes(other)) {
            return true;
        }
    }

    return false;
}

fn groupAddShape(self: *Object, shape: *Object) void {
    const payload = self.data.?;
    var grp: *Group = @ptrCast(@alignCast(payload));
    grp.objects.append(grp.allocator, shape) catch {
        @panic("Out of memory in groupAddShape()");
    };
    shape.parent = self;
}

fn groupClone(self: *const Object, newobj: *Object, allocator: Allocator) void {
    const payload = self.data.?;
    const oldgrp: *Group = @ptrCast(@alignCast(payload));

    const newgrp = Group.init(allocator);
    newobj.data = newgrp;

    for (oldgrp.objects.items) |obj| {
        const shape = obj.clone(allocator);

        newgrp.objects.append(allocator, shape) catch {
            @panic("Out of memory in groupClone()");
        };
        shape.parent = newobj;
    }
}

fn groupDeinit(self: *Object, allocator: Allocator) void {
    _ = allocator;
    const payload = self.data.?;
    const grp: *Group = @ptrCast(@alignCast(payload));
    grp.deinit();
}

fn groupBoundsOf(self: *const Object) BBox {
    const payload = self.data.?;
    const grp: *Group = @ptrCast(@alignCast(payload));

    var box = BBox{};   // Empty bounding box

    for (grp.objects.items) |obj| {
        const cbox = obj.parentSpaceBoundsOf();
        box.addBox(&cbox);
    }

    return box;
}

/// Unit sphere centered at the origin (x^2 + y^2 + z^2 = 1) ------------------
pub fn sphere(allocator: Allocator) *Object {
    return Object.init(allocator, &sphere_vtable);
}

pub fn glassSphere(allocator: Allocator) *Object {
    var obj = Object.init(allocator, &sphere_vtable);
    obj.material.transparency = 1.0;
    obj.material.refractive_index = 1.5;
    return obj;
}

var sphere_vtable = VTable {
    .intersects = sphereIntersects,
    .normalAt = sphereNormalAt,
    .includes = objectIncludes,
    .addShape = errorAddShape,
    .boundsOf = sphereBoundsOf,
    .clone = errorClone,
    .deinit = errorDeinit,
};

fn sphereIntersects(self: *const Object, r: Ray, xs: []Intersection) usize {
    // It is necessary to subract the point(0,0,0) in order to get a vector (w=0)
    // sr = vector pointing from sphere (0,0,0) to the ray origin
    const sr = r.ori - point(0,0,0);
    const a = dot(r.dir, r.dir);
    const b = 2 * dot(r.dir, sr);
    const c = dot(sr, sr) - 1;
    const discr = b * b - 4 * a * c;

    if (discr < 0) {
        return 0;
    }

    const sqrtd = @sqrt(discr);
    const t1 = (-b - sqrtd) / (2 * a);
    const t2 = (-b + sqrtd) / (2 * a);

    // Always return two intersections
    xs[0].ti = t1;
    xs[0].ob = self;
    xs[1].ti = t2;
    xs[1].ob = self;
    return 2;
}

fn sphereNormalAt(self: *const Object, obj_point: Point, px: *const Intersection) Vector {
    _ = self;
    _ = px;
    return obj_point - point(0,0,0);
}

fn objectIncludes(self: *const Object, other: *const Object) bool {
    return self == other;
}

fn sphereBoundsOf(self: *const Object) BBox {
    _ = self;
    return bbox(point(-1, -1, -1), point(1, 1, 1));
}

/// XZ Plane through the origin (x,0,z) ---------------------------------------
pub fn plane(allocator: Allocator) *Object {
    return Object.init(allocator, &plane_vtable);
}

var plane_vtable = VTable {
    .intersects = planeIntersects,
    .normalAt = planeNormalAt,
    .includes = objectIncludes,
    .addShape = errorAddShape,
    .boundsOf = planeBoundsOf,
    .clone = errorClone,
    .deinit = errorDeinit,
};

fn planeIntersects(self: *const Object, r: Ray, xs: []Intersection) usize {
    // If the ray is parallel to the XZ plane (i.e. y = 0) it does not intercept it
    if (approxEqAbs(Float, r.dir[1], 0, EPSILON)) {
        return 0;
    }
    // Intersection at t = -origin.y / direction.y
    xs[0].ti = -r.ori[1] / r.dir[1];
    xs[0].ob = self;
    return 1;
}

fn planeNormalAt(self: *const Object, obj_point: Point, px: *const Intersection) Vector {
    _ = self;
    _ = obj_point;
    _ = px;
    return vector(0,1,0);
}

fn planeBoundsOf(self: *const Object) BBox {
    _ = self;
    return bbox(point(-INFINITY, 0, -INFINITY), point(INFINITY, 0, INFINITY));
}

/// Triangle ------------------------------------------------------------------
pub const Triangle = struct {
    p1: Point,      // 3 vertices in object space
    p2: Point,
    p3: Point,
    e1: Vector,     // 2 edges
    e2: Vector,
    normal: Vector, // Normal for all points, including vertices
};

pub fn triangle(allocator: Allocator, p1: Point, p2: Point, p3: Point) *Object {
    var obj = Object.init(allocator, &triangle_vtable);
    const tri = allocator.create(Triangle)  catch {
            @panic("Out of memory in triangle()");
    };

    const e1 = p2 - p1;
    const e2 = p3 - p1;
    tri.p1 = p1;
    tri.p2 = p2;
    tri.p3 = p3;
    tri.e1 = e1;
    tri.e2 = e2;
    tri.normal = vecUnit(cross(e2, e1));

    obj.data = tri;
    return obj;
}

var triangle_vtable = VTable {
    .intersects = triangleIntersects,
    .normalAt = triangleNormalAt,
    .includes = objectIncludes,
    .addShape = errorAddShape,
    .boundsOf = triangleBoundsOf,
    .clone = triangleClone,
    .deinit = triangleDeinit,
};

fn triangleIntersects(self: *const Object, r: Ray, xs: []Intersection) usize {
    const payload = self.data.?;
    const tri: *Triangle = @ptrCast(@alignCast(payload));
    const dir_cross_e2 = cross(r.dir, tri.e2);
    const det = dot(tri.e1, dir_cross_e2);

    if (approxEqAbs(Float, det, 0, EPSILON)) {
        return 0;
    }

    const f = 1.0 / det;
    const p1_to_origin = r.ori - tri.p1;
    const u = f * dot(p1_to_origin, dir_cross_e2);

    if (u < 0 or u > 1) {
        return 0;
    }

    const origin_cross_e1 = cross(p1_to_origin, tri.e1);
    const v = f * dot(r.dir, origin_cross_e1);

    if (v < 0 or (u + v) > 1) {
        return 0;
    }

    // The ray hits the triangle
    xs[0].ti = f * dot(tri.e2, origin_cross_e1);
    xs[0].ob = self;
    xs[0].u = u;
    xs[0].v = v;
    return 1;
}

fn triangleNormalAt(self: *const Object, obj_point: Point, px: *const Intersection) Vector {
    _ = obj_point;
    _ = px;
    const payload = self.data.?;
    const tri: *Triangle = @ptrCast(@alignCast(payload));
    return tri.normal;
}

fn triangleClone(self: *const Object, newobj: *Object, allocator: Allocator) void {
    const payload = self.data.?;
    const oldtri: *Triangle = @ptrCast(@alignCast(payload));
    const newtri: *Triangle = allocator.create(Triangle)  catch {
            @panic("Out of memory in triangleClone()");
    };

    newtri.* = oldtri.*;
    newobj.data = newtri;
}

fn triangleDeinit(self: *Object, allocator: Allocator) void {
    const payload = self.data.?;
    const tri: *Triangle = @ptrCast(@alignCast(payload));
    allocator.destroy(tri);
}

fn triangleBoundsOf(self: *const Object) BBox {
    const payload = self.data.?;
    const tri: *Triangle = @ptrCast(@alignCast(payload));
    var box = BBox{};   // Empty bbox
    box.addPoint(tri.p1);
    box.addPoint(tri.p2);
    box.addPoint(tri.p3);
    return box;
}


/// Smooth Triangle ------------------------------------------------------------------
pub const SmoothTriangle = struct {
    p1: Point,      // 3 vertices in object space
    p2: Point,
    p3: Point,
    n1: Vector,     // 1 normal for each vertex
    n2: Vector,
    n3: Vector,
    e1: Vector,     // 2 edges
    e2: Vector,
};

pub fn smoothTriangle(allocator: Allocator,
                        p1: Point, p2: Point, p3: Point,
                        n1: Vector, n2: Vector, n3: Vector) *Object {
    var obj = Object.init(allocator, &smoothTriangle_vtable);
    const tri = allocator.create(SmoothTriangle)  catch {
            @panic("Out of memory in smoothTriangle()");
    };

    const e1 = p2 - p1;
    const e2 = p3 - p1;
    tri.p1 = p1;
    tri.p2 = p2;
    tri.p3 = p3;
    tri.n1 = n1;
    tri.n2 = n2;
    tri.n3 = n3;
    tri.e1 = e1;
    tri.e2 = e2;

    obj.data = tri;
    return obj;
}

var smoothTriangle_vtable = VTable {
    .intersects = smoothTriangleIntersects,
    .normalAt = smoothTriangleNormalAt,
    .includes = objectIncludes,
    .addShape = errorAddShape,
    .boundsOf = smoothTriangleBoundsOf,
    .clone = smoothTriangleClone,
    .deinit = smoothTriangleDeinit,
};

fn smoothTriangleIntersects(self: *const Object, r: Ray, xs: []Intersection) usize {
    const payload = self.data.?;
    const tri: *SmoothTriangle = @ptrCast(@alignCast(payload));
    const dir_cross_e2 = cross(r.dir, tri.e2);
    const det = dot(tri.e1, dir_cross_e2);

    if (approxEqAbs(Float, det, 0, EPSILON)) {
        return 0;
    }

    const f = 1.0 / det;
    const p1_to_origin = r.ori - tri.p1;
    const u = f * dot(p1_to_origin, dir_cross_e2);

    if (u < 0 or u > 1) {
        return 0;
    }

    const origin_cross_e1 = cross(p1_to_origin, tri.e1);
    const v = f * dot(r.dir, origin_cross_e1);

    if (v < 0 or (u + v) > 1) {
        return 0;
    }

    // The ray hits the triangle
    xs[0].ti = f * dot(tri.e2, origin_cross_e1);
    xs[0].ob = self;
    xs[0].u = u;
    xs[0].v = v;
    return 1;
}

fn smoothTriangleNormalAt(self: *const Object, obj_point: Point, px: *const Intersection) Vector {
    _ = obj_point;
    const payload = self.data.?;
    const tri: *SmoothTriangle = @ptrCast(@alignCast(payload));
    // Combine the normal at each vertex according to (u,v)
    const n1 = vecScale(tri.n2, px.u);
    const n2 = vecScale(tri.n3, px.v);
    const n3 = vecScale(tri.n1, 1 - px.u - px.v);
    return n1 + n2 + n3;
}

fn smoothTriangleClone(self: *const Object, newobj: *Object, allocator: Allocator) void {
    const payload = self.data.?;
    const oldtri: *SmoothTriangle = @ptrCast(@alignCast(payload));
    const newtri: *SmoothTriangle = allocator.create(SmoothTriangle)  catch {
            @panic("Out of memory in smoothTriangleClone()");
    };

    newtri.* = oldtri.*;
    newobj.data = newtri;
}

fn smoothTriangleDeinit(self: *Object, allocator: Allocator) void {
    const payload = self.data.?;
    const tri: *SmoothTriangle = @ptrCast(@alignCast(payload));
    allocator.destroy(tri);
}

fn smoothTriangleBoundsOf(self: *const Object) BBox {
    const payload = self.data.?;
    const tri: *SmoothTriangle = @ptrCast(@alignCast(payload));
    var box = BBox{};   // Empty bbox
    box.addPoint(tri.p1);
    box.addPoint(tri.p2);
    box.addPoint(tri.p3);
    return box;
}

/// Cube (AABB from -1 to 1) with side 2 centered at the origin ---------------
pub fn cube(allocator: Allocator) *Object {
    return Object.init(allocator, &cube_vtable);
}

var cube_vtable = VTable {
    .intersects = cubeIntersects,
    .normalAt = cubeNormalAt,
    .includes = objectIncludes,
    .addShape = errorAddShape,
    .boundsOf = cubeBoundsOf,
    .clone = errorClone,
    .deinit = errorDeinit,
};

fn cubeIntersects(self: *const Object, r: Ray, xs: []Intersection) usize {
    const xtmin, const xtmax = checkAxis(r.ori[0], r.dir[0]);
    const ytmin, const ytmax = checkAxis(r.ori[1], r.dir[1]);
    const ztmin, const ztmax = checkAxis(r.ori[2], r.dir[2]);

    const tmin = @max(xtmin, @max(ytmin, ztmin));
    const tmax = @min(xtmax, @min(ytmax, ztmax));

    if (tmin > tmax) {
        return 0;
    }

    // Always return two intersections
    xs[0].ti = tmin;
    xs[0].ob = self;
    xs[1].ti = tmax;
    xs[1].ob = self;
    return 2;
}

fn checkAxis(origin: Float, direction: Float) struct { Float, Float } {
    const tmin_numerator = (-1 - origin);
    const tmax_numerator = (1 - origin);

    // Assume FloatMode.strict -> division by zero yields +-inf
    var tmin = tmin_numerator / direction;
    var tmax = tmax_numerator / direction;

    if (tmin > tmax) {
        const temp = tmin;
        tmin = tmax;
        tmax = temp;
    }

    return .{ tmin, tmax };
}

fn cubeNormalAt(self: *const Object, obj_point: Point, px: *const Intersection) Vector {
    _ = self;
    _ = px;
    const maxc = @max(@abs(obj_point[0]), @max(@abs(obj_point[1]), @abs(obj_point[2])));

    if (maxc == @abs(obj_point[0])) {
        return vector(obj_point[0], 0, 0);
    } else if (maxc == @abs(obj_point[1])) {
        return vector(0, obj_point[1], 0);
    }

    return vector(0, 0, obj_point[2]);
}

fn cubeBoundsOf(self: *const Object) BBox {
    _ = self;
    return bbox(point(-1, -1, -1), point(1, 1, 1));
}

/// Vertical unit cylinder centered at the origin (x^2 + z^2 = 1) -------------
const Cylinder = struct {
    min_y: Float,     // Minimum Y coordinate (exclusive)
    max_y: Float,     // Maximum Y coordinate (exclusive)
    closed: bool,   // True if capped at both ends
};

pub fn cylinder(allocator: Allocator, min_y: Float, max_y: Float, closed: bool) *Object {
    var obj = Object.init(allocator, &cylinder_vtable);
    const cyl = allocator.create(Cylinder)  catch {
            @panic("Out of memory in cylinder()");
    };
    cyl.* = Cylinder{.min_y = min_y, .max_y = max_y, .closed = closed };
    obj.data = cyl;
    return obj;
}

var cylinder_vtable = VTable {
    .intersects = cylinderIntersects,
    .normalAt = cylinderNormalAt,
    .includes = objectIncludes,
    .addShape = errorAddShape,
    .clone = cylinderClone,
    .boundsOf = cylinderBoundsOf,
    .deinit = cylinderDeinit,
};

fn cylinderIntersects(self: *const Object, r: Ray, xs: []Intersection) usize {
    // a ← ray.direction.x^2 + ray.direction.z^2
    const a = r.dir[0] * r.dir[0] + r.dir[2] * r.dir[2];

    // If ray is parallel to the Y axis, check the caps
    if (approxEqAbs(Float, a, 0, EPSILON)) {
        return cylinderIntersectsCaps(self, r, xs, 0);
    }

    // b ← 2 * (ray.origin.x * ray.direction.x + ray.origin.z * ray.direction.z)
    const b = 2 * (r.ori[0] * r.dir[0] + r.ori[2] * r.dir[2]);
    // c ← ray.origin.x² + ray.origin.z² - 1
    const c = r.ori[0] * r.ori[0] + r.ori[2] * r.ori[2] - 1;
    const discr = b * b - 4 * a * c;

    if (discr < 0) {
        return 0;
    }

    const sqrtd = @sqrt(discr);
    var t0 = (-b - sqrtd) / (2 * a);
    var t1 = (-b + sqrtd) / (2 * a);

    if (t0 > t1) {
        const temp = t0;
        t0 = t1;
        t1 = temp;
    }

    const data = self.data.?;
    const cyl: *Cylinder = @ptrCast(@alignCast(data));

    // Check if intersections are within the vertical limits
    var count: usize = 0;
    const y0 = r.ori[1] + t0 * r.dir[1];
    if (cyl.min_y < y0 and y0 < cyl.max_y) {
        xs[count].ti = t0;
        xs[count].ob = self;
        count += 1;
    }

    const y1 = r.ori[1] + t1 * r.dir[1];
    if (cyl.min_y < y1 and y1 < cyl.max_y) {
        xs[count].ti = t1;
        xs[count].ob = self;
        count += 1;
    }

    return cylinderIntersectsCaps(self, r, xs, count);
}

/// Checks if the ray intersepts the cylinder at one or both of its caps
fn cylinderIntersectsCaps(self: *const Object, r: Ray, xs: []Intersection, xs_len: usize) usize {
    const data = self.data.?;
    const cyl: *Cylinder = @ptrCast(@alignCast(data));

    if (!cyl.closed) {
        return xs_len;
    }

    var count = xs_len;

    // Check lower cap
    const t0 = (cyl.min_y - r.ori[1]) / r.dir[1];
    if (cylinderCheckCap(r, t0)) {
        xs[count].ti = t0;
        xs[count].ob = self;
        count += 1;
    }

    // Check upper cap
    const t1 = (cyl.max_y - r.ori[1]) / r.dir[1];
    if (cylinderCheckCap(r, t1)) {
        xs[count].ti = t1;
        xs[count].ob = self;
        count += 1;
    }

    return count;
}

/// Checks if the intersection at `t` is within a radius of 1 from the Y axis.
fn cylinderCheckCap(r: Ray, t: Float) bool {
    const x = r.ori[0] + t * r.dir[0];
    const z = r.ori[2] + t * r.dir[2];
    return (x * x + z * z) <= 1;
}

fn cylinderNormalAt(self: *const Object, obj_point: Point, px: *const Intersection) Vector {
    _ = px;
    const data = self.data.?;
    const cyl: *Cylinder = @ptrCast(@alignCast(data));
    const dist = obj_point[0] * obj_point[0] + obj_point[2] * obj_point[2];

    if (dist < 1) {
        if (obj_point[1] >= (cyl.max_y - EPSILON)) {        // Upper cap?
            return vector(0, 1, 0);
        } else if (obj_point[1] <= (cyl.min_y + EPSILON)) { // Lower cap?
            return vector(0, -1, 0);
        }
    }

    return vector(obj_point[0], 0, obj_point[2]);
}

fn cylinderClone(self: *const Object, newobj: *Object, allocator: Allocator) void {
    const payload = self.data.?;
    const oldcyl: *Cylinder = @ptrCast(@alignCast(payload));
    const newcyl: *Cylinder = allocator.create(Cylinder)  catch {
            @panic("Out of memory in cylinderClone()");
    };

    newcyl.* = oldcyl.*;
    newobj.data = newcyl;
}

fn cylinderDeinit(self: *Object, allocator: Allocator) void {
    const payload = self.data.?;
    const cyl: *Cylinder = @ptrCast(@alignCast(payload));
    allocator.destroy(cyl);
}

fn cylinderBoundsOf(self: *const Object) BBox {
    const data = self.data.?;
    const cyl: *Cylinder = @ptrCast(@alignCast(data));
    return bbox(point(-1, cyl.min_y, -1), point(1, cyl.max_y, 1));
}

/// Double cone centered at the origin ----------------------------------------
pub fn cone(allocator: Allocator, min_y: Float, max_y: Float, closed: bool) *Object {
    var obj = Object.init(allocator, &cone_vtable);
    // Use the same structure as a cylinder
    const con = allocator.create(Cylinder)  catch {
            @panic("Out of memory in cylinder()");
    };

    con.* = Cylinder{.min_y = min_y, .max_y = max_y, .closed = closed };
    obj.data = con;
    return obj;
}

var cone_vtable = VTable {
    .intersects = coneIntersects,
    .normalAt = coneNormalAt,
    .includes = objectIncludes,
    .addShape = errorAddShape,
    .boundsOf = coneBoundsOf,
    .clone = cylinderClone,
    .deinit = cylinderDeinit,
};

fn coneIntersects(self: *const Object, r: Ray, xs: []Intersection) usize {
     // a ← ray.direction.x² - ray.direction.y² + ray.direction.z²
    const a = r.dir[0] * r.dir[0] - r.dir[1] * r.dir[1] + r.dir[2] * r.dir[2];
    // b ← 2 * (ray.origin.x * ray.direction.x -ray.origin.y * ray.direction.y + ray.origin.z * ray.direction.z)
    const b = 2 * (r.ori[0] * r.dir[0] - r.ori[1] * r.dir[1] + r.ori[2] * r.dir[2]);
    // c ← ray.origin.x² - ray.origin.y² + ray.origin.z²
    const c = r.ori[0] * r.ori[0] - r.ori[1] * r.ori[1] + r.ori[2] * r.ori[2];
    const data = self.data.?;
    const con: *Cylinder = @ptrCast(@alignCast(data));

    var count: usize = 0;

    if (!approxEqAbs(Float, a, 0, EPSILON)) {
        // Common case, a != 0
        var discr = b * b - 4 * a * c;
        if (approxEqAbs(Float, discr, 0, 0.00001)) {
            discr = 0;
        }

        if (discr < 0) {
            return 0;
        }

        const sqrtd = @sqrt(discr);
        var t0 = (-b - sqrtd) / (2 * a);
        var t1 = (-b + sqrtd) / (2 * a);

        if (t0 > t1) {
            const temp = t0;
            t0 = t1;
            t1 = temp;
        }

        // Check if intersections are within the vertical limits
        const y0 = r.ori[1] + t0 * r.dir[1];
        if (con.min_y < y0 and y0 < con.max_y) {
            xs[count].ti = t0;
            xs[count].ob = self;
            count += 1;
        }

        const y1 = r.ori[1] + t1 * r.dir[1];
        if (con.min_y < y1 and y1 < con.max_y) {
            xs[count].ti = t1;
            xs[count].ob = self;
            count += 1;
        }

    } else {
        // a == 0
        // If both a and b are zero, the ray misses the cone
        if (approxEqAbs(Float, b, 0, EPSILON)) {
            return 0;
        }
        // But if b is nonzero, then the ray is parallel to the cone and intercepts it one time
        xs[count].ti = -c / b;
        xs[count].ob = self;
        count += 1;
    }

    // If the cone is uncapped, nothing more to check
    if (!con.closed) {
        return count;
    }

    // Check the caps
    return coneIntersectsCaps(self, r, xs, count);
}

/// Checks if the ray intersepts the cone at one or both of its caps
fn coneIntersectsCaps(self: *const Object, r: Ray, xs: []Intersection, xs_len: usize) usize {
    const data = self.data.?;
    const con: *Cylinder = @ptrCast(@alignCast(data));

    var count = xs_len;

    // Check lower cap
    const t0 = (con.min_y - r.ori[1]) / r.dir[1];
    if (coneCheckCap(r, t0, con.min_y * con.min_y)) {
        xs[count].ti = t0;
        xs[count].ob = self;
        count += 1;
    }

    // Check upper cap
    const t1 = (con.max_y - r.ori[1]) / r.dir[1];
    if (coneCheckCap(r, t1, con.max_y * con.max_y)) {
        xs[count].ti = t1;
        xs[count].ob = self;
        count += 1;
    }

    return count;
}

/// Checks if the intersection at `t` is within a radius of y from the Y axis.
fn coneCheckCap(r: Ray, t: Float, y2: Float) bool {
    const x = r.ori[0] + t * r.dir[0];
    const z = r.ori[2] + t * r.dir[2];
    return (x * x + z * z) <= y2;
}

fn coneNormalAt(self: *const Object, obj_point: Point, px: *const Intersection) Vector {
    _ = px;
    const data = self.data.?;
    const con: *Cylinder = @ptrCast(@alignCast(data));
    const y = @sqrt(obj_point[0] * obj_point[0] + obj_point[2] * obj_point[2]);

    if (obj_point[1] >= (con.max_y - EPSILON)) {        // Upper cap?
        return vector(0, 1, 0);
    } else if (obj_point[1] <= (con.min_y + EPSILON)) { // Lower cap?
        return vector(0, -1, 0);
    }

    return vector(obj_point[0],
                  if (obj_point[1] > 0) -y else y,
                  obj_point[2]);
}

fn coneBoundsOf(self: *const Object) BBox {
    const data = self.data.?;
    const con: *Cylinder = @ptrCast(@alignCast(data));
    const limit = @max(@abs(con.min_y), @abs(con.max_y));
    return bbox(point(-limit, con.min_y, -limit), point(limit, con.max_y, limit));
}

/// Constructive Solid Geometry (CSG) -----------------------------------------
pub const CsgOp = enum {
    csg_union,      // Union
    csg_inter,      // Intersection
    csg_diff,       // Difference
};

const Csg = struct {
    left: *Object,  // Left object
    right: *Object, // Right object
    op: CsgOp,      // Operation
};

pub fn csg(allocator: Allocator, op: CsgOp, left: *Object, right: *Object) *Object {
    var obj = Object.init(allocator, &csg_vtable);
    const _csg = allocator.create(Csg)  catch {
            @panic("Out of memory in csg()");
    };
    _csg.* = Csg{ .left = left, .right = right, .op = op };
    obj.data = _csg;
    left.parent = obj;
    right.parent = obj;
    return obj;
}

var csg_vtable = VTable {
    .intersects = csgIntersects,
    .normalAt = errorNormalAt,
    .includes = csgIncludes,
    .addShape = errorAddShape,
    .boundsOf = csgBoundsOf,
    .clone = csgClone,
    .deinit = csgDeinit,
};

/// Checks if the ray intersepts either the left or the right sub-object
fn csgIntersects(self: *const Object, r: Ray, xs: []Intersection) usize {
    var xs_temp: [MAX_INTERSECTIONS]Intersection = undefined;
    const payload = self.data.?;
    const _csg: *Csg = @ptrCast(@alignCast(payload));

    const count_left = _csg.left.intersects(r, xs_temp[0..]);
    const count_right = _csg.right.intersects(r, xs_temp[count_left..]);
    const count = count_left + count_right;

    // Sort the xs[] array if there is more than 1 intersection
    if (count > 1) {
        sortIntersections(xs_temp[0..count]);
    }

    // In worst case must have room for all intersections
    if (xs.len < count) {
        @panic("Not enough xs[] slots in csgIntersects");
    }

    // Scan the intersections in xs_temp[], selecting only the allowed ones for xs[]
    var i: usize = 0;   // input index (xs_temp)
    var j: usize = 0;   // output index (xs)

    // Begin outside of both children
    var inl = false;
    var inr = false;

    while (i < count) : (i += 1) {
        const lhit = _csg.left.includes(xs_temp[i].ob);

        // If this intersection is allowed, add it to the result list xs[]
        if (csgIntersectionAllowed(_csg.op, lhit, inl, inr)) {
            xs[j] = xs_temp[i];
            j += 1;
        }

        // Depending on which object was hit, toggle either inl or inr
        if (lhit) {
            inl = !inl;
        } else {
            inr = !inr;
        }
    }

    return j;
}

fn csgIntersectionAllowed(op: CsgOp, lhit: bool, inl: bool, inr: bool) bool {
    return switch (op) {
        .csg_union => (lhit and !inr) or (!lhit and !inl),
        .csg_diff => (lhit and !inr) or (!lhit and inl),
        .csg_inter => (lhit and inr) or (!lhit and inl),
    };
}

fn csgIncludes(self: *const Object, other: *const Object) bool {
    const payload = self.data.?;
    const _csg: *Csg = @ptrCast(@alignCast(payload));

    if (_csg.left.includes(other)) {
        return true;
    }

    return _csg.right.includes(other);
}

pub fn csgClone(self: *const Object, newobj: *Object, allocator: Allocator) void {
    const payload = self.data.?;
    const oldcsg: *Csg = @ptrCast(@alignCast(payload));
    const newcsg: *Csg = allocator.create(Csg)  catch {
            @panic("Out of memory in csgClone()");
    };

    var newleft  = oldcsg.left.clone(allocator);
    newcsg.left = newleft;
    newleft.parent = newobj;

    var newright = oldcsg.right.clone(allocator);
    newcsg.right = newright;
    newright.parent = newobj;

    newcsg.op = oldcsg.op;
    newobj.data = newcsg;
}

fn csgDeinit(self: *Object, allocator: Allocator) void {
    const payload = self.data.?;
    const _csg: *Csg = @ptrCast(@alignCast(payload));
    _csg.left.deinit(allocator);
    _csg.right.deinit(allocator);
    allocator.destroy(_csg);
}

fn csgBoundsOf(self: *const Object) BBox {
    const payload = self.data.?;
    const _csg: *Csg = @ptrCast(@alignCast(payload));

    var box = BBox{};   // Empty bounding box

    const lbbox = _csg.left.parentSpaceBoundsOf();
    const rbbox = _csg.right.parentSpaceBoundsOf();
    
    box.addBox(&lbbox);
    box.addBox(&rbbox);

    return box;
}

// Object tests ===============================================================
const expect = std.testing.expect;
const vecEqual = mth.vecEqual;

const InterceptTest = struct {
    ray: Ray,       // Test ray
    n: usize = 0,   // Number of intersections
    t1: Float = 0,    // Time of 1st intersection
    t2: Float = 0,    // Time of 2nd intersection
};

const cubeInterceptTests = [_]InterceptTest{
    .{ .ray = Ray{.ori = point(5, 0.5, 0), .dir = vector(-1, 0, 0)}, .n = 2, .t1 = 4, .t2 = 6 }, // +x
    .{ .ray = Ray{.ori = point(-5, 0.5, 0), .dir = vector(1, 0, 0)}, .n = 2, .t1 = 4, .t2 = 6 }, // -x
    .{ .ray = Ray{.ori = point(0.5, 5, 0), .dir = vector(0, -1, 0)}, .n = 2, .t1 = 4, .t2 = 6 }, // +y
    .{ .ray = Ray{.ori = point(0.5, -5, 0), .dir = vector(0, 1, 0)}, .n = 2, .t1 = 4, .t2 = 6 }, // -y
    .{ .ray = Ray{.ori = point(0.5, 0, 5), .dir = vector(0, 0, -1)}, .n = 2, .t1 = 4, .t2 = 6 }, // +z 
    .{ .ray = Ray{.ori = point(0.5, 0, -5), .dir = vector(0, 0, 1)}, .n = 2, .t1 = 4, .t2 = 6 }, // -z
    .{ .ray = Ray{.ori = point(0, 0.5, 0), .dir = vector(0, 0, 1)}, .n = 2, .t1 = -1, .t2 = 1 }, // inside

    .{ .ray = Ray{.ori = point(-2, 0, 0), .dir = vector(0.2673, 0.5345, 0.8018)}}, // miss
    .{ .ray = Ray{.ori = point(0, -2, 0), .dir = vector(0.8018, 0.2673, 0.5345)}}, // miss
    .{ .ray = Ray{.ori = point(0, 0, -2), .dir = vector(0.5345, 0.8018, 0.2673)}}, // miss
    .{ .ray = Ray{.ori = point(2, 0, 2), .dir = vector(0, 0, -1)}}, // miss
    .{ .ray = Ray{.ori = point(0, 2, 2), .dir = vector(0, -1, 0)}}, // miss
    .{ .ray = Ray{.ori = point(2, 2, 0), .dir = vector(-1, 0, 0)}}, // miss
};

test "Cube Intersections" {
    const allocator: Allocator = std.testing.allocator;
    var xs: [MAX_INTERSECTIONS]Intersection = undefined;
    const shape = cube(allocator);
    defer shape.deinit(allocator);

    for (cubeInterceptTests) |tst| {
        const n = shape.intersects(tst.ray, &xs);
        try expect(n == tst.n);
        if (n == 2) {
            try expect(xs[0].ti == tst.t1);
            try expect(xs[1].ti == tst.t2);
        }
    }
}

const NormalTest = struct {
    pnt: Point,
    nor: Vector,
};

const cubeNormalTests = [_]NormalTest {
    .{ .pnt = point(1, 0.5, -0.8), .nor = vector(1, 0, 0) },
    .{ .pnt = point(-1, -0.2, 0.9), .nor = vector(-1, 0, 0) },
    .{ .pnt = point(-0.4, 1, -0.1), .nor = vector(0, 1, 0) },
    .{ .pnt = point(0.3, -1, -0.7), .nor = vector(0, -1, 0) },
    .{ .pnt = point(-0.6, 0.3, 1), .nor = vector(0, 0, 1) },
    .{ .pnt = point(0.4, 0.4, -1), .nor = vector(0, 0, -1) },
    .{ .pnt = point(1, 1, 1), .nor = vector(1, 0, 0) },
    .{ .pnt = point(-1, -1, -1), .nor = vector(-1, 0, 0) },
};

test "Cube Normals" {
    const allocator: Allocator = std.testing.allocator;
    const shape = cube(allocator);
    defer shape.deinit(allocator);
    const dummy_inter: Intersection = undefined;

    for (cubeNormalTests) |tst| {
        const nor = shape.normalAt(tst.pnt, &dummy_inter);
        try expect(vecEqual(nor, tst.nor));
    }
}

// Infinite cylinder
const cylinderInterceptTests = [_]InterceptTest{
    .{ .ray = Ray{.ori = point(1, 0, -5),   .dir = vector(0, 0, 1)},   .n = 2, .t1 = 5,  .t2 = 5 },
    .{ .ray = Ray{.ori = point(0, 0, -5),   .dir = vector(0, 0, 1)},   .n = 2, .t1 = 4,  .t2 = 6 },
    .{ .ray = Ray{.ori = point(0.5, 0, -5), .dir = vector(0.1, 1, 1)}, .n = 2, .t1 = 6.80800, .t2 = 7.08870 },
    .{ .ray = Ray{.ori = point(1, 0, 0),  .dir = vector(0, 1, 0)}}, // miss
    .{ .ray = Ray{.ori = point(0, 0, 0),  .dir = vector(0, 1, 0)}}, // miss
    .{ .ray = Ray{.ori = point(0, 0, -5), .dir = vector(1, 1, 1)}}, // miss
};

// Truncated uncapped cylinder (ymin=1, ymax=2)
const cylinderInterceptTests2 = [_]InterceptTest{
    .{ .ray = Ray{.ori = point(0, 1.5, 0),   .dir = vector(0.1, 1, 0)}}, // miss
    .{ .ray = Ray{.ori = point(0, 3, -5),  .dir = vector(0, 0, 1)}}, // miss
    .{ .ray = Ray{.ori = point(0, 0, -5),  .dir = vector(0, 0, 1)}}, // miss
    .{ .ray = Ray{.ori = point(0, 2, -5),  .dir = vector(0, 0, 1)}}, // miss
    .{ .ray = Ray{.ori = point(0, 1, -5),  .dir = vector(0, 0, 1)}}, // miss
    .{ .ray = Ray{.ori = point(0, 1.5, -2),  .dir = vector(0, 0, 1)}, .n = 2},
};

// Truncated capped cylinder (ymin=1, ymax=2)
const cylinderInterceptTests3 = [_]InterceptTest{
    .{ .ray = Ray{.ori = point(0, 3, 0),  .dir = vector(0, -1, 0)}, .n = 2},
    .{ .ray = Ray{.ori = point(0, 3, -2), .dir = vector(0, -1, 2)}, .n = 2},
    .{ .ray = Ray{.ori = point(0, 4, -2), .dir = vector(0, -1, 1)}, .n = 2},
    .{ .ray = Ray{.ori = point(0, 0, -2),  .dir = vector(0, 1, 2)}, .n = 2},
    .{ .ray = Ray{.ori = point(0, -1, -2),  .dir = vector(0, 1, 1)}, .n = 2},
};

test "Cylinder Intersections" {
    const allocator: Allocator = std.testing.allocator;
    var xs: [MAX_INTERSECTIONS]Intersection = undefined;
    var shape = cylinder(allocator, -1.9e99, 1.9e99, false);

    // Infinite cylinder
    for (cylinderInterceptTests) |tst| {
        const ori = tst.ray.ori;
        const dir = vecUnit(tst.ray.dir);
        const n = shape.intersects(Ray{.ori=ori, .dir=dir}, &xs);
        try expect(n == tst.n);
        if (n == 2) {
            try expect(approxEqAbs(Float, xs[0].ti, tst.t1, 0.00001));
            try expect(approxEqAbs(Float, xs[1].ti, tst.t2, 0.00001));
        }
    }

    shape.deinit(allocator);

    // Truncated uncapped cylinder
    shape = cylinder(allocator, 1, 2, false);

    for (cylinderInterceptTests2) |tst| {
        const ori = tst.ray.ori;
        const dir = vecUnit(tst.ray.dir);
        const n = shape.intersects(Ray{.ori=ori, .dir=dir}, &xs);
        try expect(n == tst.n);
    }

    shape.deinit(allocator);

    // Truncated capped cylinder
    shape = cylinder(allocator, 1, 2, true);
    defer shape.deinit(allocator);

    for (cylinderInterceptTests3) |tst| {
        const ori = tst.ray.ori;
        // If we normalize the ray's direction here, rounding errors will make
        // the distance squared in check_cap to be slightly greater than 1 and
        // the test will fail. With the non-normalized direction the distance
        // squared is exactly 1 and the test succeeds.
        // const dir = vecUnit(tst.ray.dir);
        const dir = tst.ray.dir;
        const n = shape.intersects(Ray{.ori=ori, .dir=dir}, &xs);
        try expect(n == tst.n);
    }
}

const cylinderNormalTests = [_]NormalTest {
    // Walls
    .{ .pnt = point(1, 0, 0),  .nor = vector(1, 0,  0) },
    .{ .pnt = point(0, 5, -1), .nor = vector(0, 0, -1) },
    .{ .pnt = point(0, -2, 1), .nor = vector(0, 0,  1) },
    .{ .pnt = point(-1, 1, 0), .nor = vector(-1, 0, 0) },
    // Caps
    .{ .pnt = point(0, 1, 0),   .nor = vector(0, -1,  0) },
    .{ .pnt = point(0.5, 1, 0), .nor = vector(0, -1,  0) },
    .{ .pnt = point(0, 1, 0.5), .nor = vector(0, -1,  0) },
    .{ .pnt = point(0, 2, 0),   .nor = vector(0, 1,  0) },
    .{ .pnt = point(0.5, 2, 0), .nor = vector(0, 1,  0) },
    .{ .pnt = point(0, 2, 0.5), .nor = vector(0, 1,  0) },
};

test "Cylinder Normals" {
    const allocator: Allocator = std.testing.allocator;
    var shape = cylinder(allocator, 1, 2, true);
    defer shape.deinit(allocator);
    var cyl: *Cylinder = @ptrCast(@alignCast(shape.data.?));
    cyl.closed = true;
    const dummy_inter: Intersection = undefined;

    for (cylinderNormalTests) |tst| {
        const nor = shape.normalAt(tst.pnt, &dummy_inter);
        try expect(vecEqual(nor, tst.nor));
    }
}

// Infinite cone
const coneInterceptTests = [_]InterceptTest{
    .{ .ray = Ray{.ori = point(0, 0, -5), .dir = vector(0, 0, 1)},     .n = 2, .t1 = 5,  .t2 = 5 },
    .{ .ray = Ray{.ori = point(0, 0, -5), .dir = vector(1, 1, 1)},     .n = 2, .t1 = 8.66025,  .t2 = 8.66025 },
    .{ .ray = Ray{.ori = point(1, 1, -5), .dir = vector(-0.5, -1, 1)}, .n = 2, .t1 = 4.55005, .t2 = 49.4499 },
    .{ .ray = Ray{.ori = point(0, 0, -1), .dir = vector(0, 1, 1)},     .n = 1, .t1 = 0.707106 },
};

const coneInterceptTests2 = [_]InterceptTest{
    .{ .ray = Ray{.ori = point(0, 0, -5),    .dir = vector(0, 1, 0)}, .n = 0},
    .{ .ray = Ray{.ori = point(0, 0, -0.25), .dir = vector(0, 1, 1)}, .n = 2},
    .{ .ray = Ray{.ori = point(0, 0, -0.25), .dir = vector(0, 1, 0)}, .n = 4},
};

test "Cone Intersections" {
    const allocator: Allocator = std.testing.allocator;
    var xs: [MAX_INTERSECTIONS]Intersection = undefined;
    var shape = cone(allocator, -1.9e99, 1.9e99, false);

    // Infinite cone
    for (coneInterceptTests) |tst| {
        const ori = tst.ray.ori;
        const dir = vecUnit(tst.ray.dir);
        const n = shape.intersects(Ray{.ori=ori, .dir=dir}, &xs);
        try expect(n == tst.n);
        if (n > 0) {
            try expect(approxEqAbs(Float, xs[0].ti, tst.t1, 0.0001));
            if (n == 2) {
                try expect(approxEqAbs(Float, xs[1].ti, tst.t2, 0.0001));
            }
        }
    }

    shape.deinit(allocator);

    // Truncated capped cone
    shape = cone(allocator, -0.5, 0.5, true);
    defer shape.deinit(allocator);

    for (coneInterceptTests2) |tst| {
        const ori = tst.ray.ori;
        const dir = vecUnit(tst.ray.dir);
        const n = shape.intersects(Ray{.ori=ori, .dir=dir}, &xs);
        try expect(n == tst.n);
    }
}

test "worldToObject" {
    const allocator: Allocator = std.testing.allocator;
    var g1 = group(allocator);
    defer g1.deinit(allocator); // Will free all the children

    g1.itrans = invRotationY(std.math.pi / 2.0);
    var g2 = group(allocator);
    g2.itrans = invScaling(2, 2, 2);
    g1.addShape(g2);
    var s = sphere(allocator);
    s.itrans = invTranslation(5, 0, 0);
    g2.addShape(s);
    const p = s.worldToObject(point(-2, 0, -10));
    try expect(mth.pntEqual(p, point(0, 0, -1)));
}

test "normalToWorld" {
    const allocator: Allocator = std.testing.allocator;
    var g1 = group(allocator);
    defer g1.deinit(allocator); // Will free all the children

    g1.itrans = invRotationY(std.math.pi / 2.0);
    var g2 = group(allocator);
    g2.itrans = invScaling(1, 2, 3);
    g1.addShape(g2);
    var s = sphere(allocator);
    s.itrans = invTranslation(5, 0, 0);
    g2.addShape(s);

    const n = s.normalToWorld(vector(@sqrt(3.0)/3.0,@sqrt(3.0)/3.0,@sqrt(3.0)/3.0));
    try expect(vecEqual(n, vector(0.28571427, 0.42857146, -0.8571429)));
}

test "Triangle Intersections" {
    const allocator: Allocator = std.testing.allocator;
    var xs: [MAX_INTERSECTIONS]Intersection = undefined;
    var shape = triangle(allocator, point(0,1,0), point(-1,0,0), point(1,0,0));
    defer shape.deinit(allocator);

    var r = Ray{.ori = point(0,-1,-2), .dir=vector(0,1,0)};
    var count = shape.intersects(r, &xs);
    try expect(count == 0);

    r = Ray{.ori = point(1,1,-2), .dir=vector(0,0,1)};
    count = shape.intersects(r, &xs);
    try expect(count == 0);

    // Ray misses the p1-p2 edge
    r = Ray{.ori = point(-1,1,-2), .dir=vector(0,0,1)};
    count = shape.intersects(r, &xs);
    try expect(count == 0);

    // Ray misses the p2-p3 edge
    r = Ray{.ori = point(0,-1,-2), .dir=vector(0,0,1)};
    count = shape.intersects(r, &xs);
    try expect(count == 0);

    // Ray hits the triangle
    r = Ray{.ori = point(0,0.5,-2), .dir=vector(0,0,1)};
    count = shape.intersects(r, &xs);
    try expect(count == 1 and xs[0].ti == 2);
}

const IntersectionAllowedTest = struct {
    op: CsgOp,  // Operation
    lhit: bool, // True if left shape was hit, false if right shape was hit
    inl: bool,  // Hit occurred inside the left shape
    inr: bool,  // Hit occurred inside the right shape
    res: bool,  // Result
};

const intersectionAllowedTests = [_]IntersectionAllowedTest{
    // Union
    .{ .op = .csg_union, .lhit = true, .inl = true, .inr = true, .res = false },
    .{ .op = .csg_union, .lhit = true, .inl = true, .inr = false, .res = true },
    .{ .op = .csg_union, .lhit = true, .inl = false, .inr = true, .res = false },
    .{ .op = .csg_union, .lhit = true, .inl = false, .inr = false, .res = true },
    .{ .op = .csg_union, .lhit = false, .inl = true, .inr = true, .res = false },
    .{ .op = .csg_union, .lhit = false, .inl = true, .inr = false, .res = false },
    .{ .op = .csg_union, .lhit = false, .inl = false, .inr = true, .res = true },
    .{ .op = .csg_union, .lhit = false, .inl = false, .inr = false, .res = true },
    // Intersection
    .{ .op = .csg_inter, .lhit = true, .inl = true, .inr = true, .res = true },
    .{ .op = .csg_inter, .lhit = true, .inl = true, .inr = false, .res = false },
    .{ .op = .csg_inter, .lhit = true, .inl = false, .inr = true, .res = true },
    .{ .op = .csg_inter, .lhit = true, .inl = false, .inr = false, .res = false },
    .{ .op = .csg_inter, .lhit = false, .inl = true, .inr = true, .res = true },
    .{ .op = .csg_inter, .lhit = false, .inl = true, .inr = false, .res = true },
    .{ .op = .csg_inter, .lhit = false, .inl = false, .inr = true, .res = false },
    .{ .op = .csg_inter, .lhit = false, .inl = false, .inr = false, .res = false },
    // Difference
    .{ .op = .csg_diff, .lhit = true, .inl = true, .inr = true, .res = false },
    .{ .op = .csg_diff, .lhit = true, .inl = true, .inr = false, .res = true },
    .{ .op = .csg_diff, .lhit = true, .inl = false, .inr = true, .res = false },
    .{ .op = .csg_diff, .lhit = true, .inl = false, .inr = false, .res = true },
    .{ .op = .csg_diff, .lhit = false, .inl = true, .inr = true, .res = true },
    .{ .op = .csg_diff, .lhit = false, .inl = true, .inr = false, .res = true },
    .{ .op = .csg_diff, .lhit = false, .inl = false, .inr = true, .res = false },
    .{ .op = .csg_diff, .lhit = false, .inl = false, .inr = false, .res = false },
};

test "csgIntersectionAllowed" {
    for (intersectionAllowedTests) |tst| {
        const res = csgIntersectionAllowed(tst.op, tst.lhit, tst.inl, tst.inr);
        try expect(res == tst.res);
    }
}

test "csgIntersects" {
    const allocator = std.testing.allocator;
    var xs: [MAX_INTERSECTIONS]Intersection = undefined;

    // A ray misses a CSG object
    const s = sphere(allocator);
    const c = cube(allocator);
    const c1 = csg(allocator, .csg_union, s, c);
    defer c1.deinit(allocator); // Recursively deinits left/right objects
    const r1 = Ray{ .ori = point(0, 2, -5), .dir = vector(0, 0, 1)};
    const count = csgIntersects(c1, r1, &xs);

    try expect(count == 0);
}