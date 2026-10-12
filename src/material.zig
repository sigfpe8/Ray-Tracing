const mth = @import("math.zig");
const Float = mth.Float;
const EPSILON = mth.EPSILON;

const pat = @import("pattern.zig");
const Pattern = pat.Pattern;

pub const Material = struct {
    pattern: Pattern = Pattern{},
    color: Color = Color{1, 1, 1},
    ambient: Float = 0.1,
    diffuse: Float = 0.9,
    specular: Float = 0.9,
    shininess: Float = 200.0,
    reflective: Float = 0,
    transparency: Float = 0,
    refractive_index: Float = 1.0,
};

pub const glassMaterialBook = Material{
    .color = Color{0.8, 0.8, 0.9},
    .ambient = 0,
    .diffuse = 0.2,
    .specular = 0.9,
    .shininess = 300,
    .transparency = 0.8,
    .refractive_index = 1.57,
};

pub const glassMaterial = Material{
    .color = Color{0.8, 0.8, 0.9},
    .ambient = 0.1,
    .diffuse = 0.1,
    .specular = 1.0,
    .shininess = 300,
    .transparency = 1.0,
    .refractive_index = 1.52,
    .reflective = 0.1,
};

pub const testMaterial = Material{
    .color = gold,
};

// This should probably go to color.zig later
pub const Color = @Vector(3, Float);

/// Multiply a vector by a scalar
pub fn colScale(c: Color, s: Float) Color {
    const tv: Color = @splat(s);
    return c * tv;
}

/// Checks whether two colors are equal within the epsilon tolerance
pub fn colEqual(v1: Color, v2: Color) bool {
    const tv = @abs(v1 - v2) < @as(Color, @splat(EPSILON));
    return @reduce(.And, tv);
}

pub const black = Color{0, 0, 0};
pub const red   = Color{1, 0, 0};
pub const green = Color{0, 1, 0};
pub const blue  = Color{0, 0, 1};
pub const white = Color{1, 1, 1};

pub const yellow = Color{1, 1, 0};
pub const gold = Color{255.0/255.0, 215.0/255.0, 51.0/255.0};
pub const mustardYellow = Color{ 255.0/255.0, 219.0/255.0, 88.0/255.0};
pub const lemonYellow = Color{255.0/255.0, 250.0/255.0, 51.0/255.0};
pub const pastelYellow = Color{255.0/255.0, 250.0/255.0, 160.0/255.0};


