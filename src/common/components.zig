//! WORK-IN-PROGRESS
//!
const std = @import("std");
const rl = @import("raylib");

/// A Transform component representing position, rotation, and scale in 3D space
pub const Transform = struct {
    matrix: rl.Matrix,

    pub fn init() Transform {
        return Transform{
            .matrix = rl.Matrix.identity(),
        };
    }

    /// Initializes a Transform from position, rotation (Euler angles in radians), and scale
    pub fn initFromPosRotScale(position: rl.Vector3, rotation: rl.Vector3, _scale: rl.Vector3) Transform {
        var transform = Transform{
            .matrix = rl.Matrix.scale(_scale.x, _scale.y, _scale.z),
        };
        transform.matrix = transform.matrix.multiply(rl.Matrix.rotateXYZ(rotation));
        transform.matrix = transform.matrix.multiply(rl.Matrix.translate(position.x, position.y, position.z));
        return transform;
    }

    /// Rotates the transformation matrix
    pub fn rotate(self: *Transform, rotation: rl.Vector3) void {
        if (isRotationInRadians(rotation) == false) std.debug.panic("rotation vector components appear to be in degrees, but radians are expected: {{ {d}, {d}, {d} }}\n", .{ rotation.x, rotation.y, rotation.z });
        self.matrix = self.matrix.multiply(rl.Matrix.rotateXYZ(rotation));
    }

    /// Translates the transformation matrix
    pub fn translate(self: *Transform, translation: rl.Vector3) void {
        self.matrix = self.matrix.multiply(rl.Matrix.translate(translation.x, translation.y, translation.z));
    }

    /// Scales the transformation matrix
    pub fn scale(self: *Transform, _scale: rl.Vector3) void {
        self.matrix = self.matrix.multiply(rl.Matrix.scale(_scale.x, _scale.y, _scale.z));
    }

    /// Sets position in the transformation matrix
    pub fn setPosition(self: *Transform, position: rl.Vector3) void {
        self.matrix.m12 = position.x;
        self.matrix.m13 = position.y;
        self.matrix.m14 = position.z;
    }

    /// Gets position from the transformation matrix
    pub fn getPosition(self: *const Transform) rl.Vector3 {
        return rl.Vector3{
            .x = self.matrix.m12,
            .y = self.matrix.m13,
            .z = self.matrix.m14,
        };
    }

    /// Gets rotation as a quaternion
    pub fn getRotation(self: *const Transform) rl.Quaternion {
        const m = self.matrix;
        var sx = std.math.sqrt(m.m0 * m.m0 + m.m1 * m.m1 + m.m2 * m.m2);
        var sy = std.math.sqrt(m.m4 * m.m4 + m.m5 * m.m5 + m.m6 * m.m6);
        var sz = std.math.sqrt(m.m8 * m.m8 + m.m9 * m.m9 + m.m10 * m.m10);
        const EPS: f32 = 1e-8;
        if (sx < EPS) sx = 1.0;
        if (sy < EPS) sy = 1.0;
        if (sz < EPS) sz = 1.0;

        const rot_m = rl.Matrix{
            .m0 = m.m0 / sx,
            .m1 = m.m1 / sx,
            .m2 = m.m2 / sx,
            .m3 = 0.0,
            .m4 = m.m4 / sy,
            .m5 = m.m5 / sy,
            .m6 = m.m6 / sy,
            .m7 = 0.0,
            .m8 = m.m8 / sz,
            .m9 = m.m9 / sz,
            .m10 = m.m10 / sz,
            .m11 = 0.0,
            .m12 = 0.0,
            .m13 = 0.0,
            .m14 = 0.0,
            .m15 = 1.0,
        };
        return rl.Quaternion.fromMatrix(rot_m);
    }

    /// Gets Euler angles (roll=X, pitch=Y, yaw=Z) in radians
    pub fn getEuler(self: *const Transform) rl.Vector3 {
        // Convert quaternion to Euler angles (roll=X, pitch=Y, yaw=Z) in radians.
        const q = self.getRotation();
        const sinr_cosp = 2.0 * (q.w * q.x + q.y * q.z);
        const cosr_cosp = 1.0 - 2.0 * (q.x * q.x + q.y * q.y);
        const roll = std.math.atan2(sinr_cosp, cosr_cosp);

        const sinp = 2.0 * (q.w * q.y - q.z * q.x);
        var pitch: f32 = 0.0;
        if (sinp >= 1.0) {
            pitch = @as(f32, std.math.pi) / 2.0;
        } else if (sinp <= -1.0) {
            pitch = -(@as(f32, std.math.pi) / 2.0);
        } else {
            pitch = std.math.asin(sinp);
        }

        const siny_cosp = 2.0 * (q.w * q.z + q.x * q.y);
        const cosy_cosp = 1.0 - 2.0 * (q.y * q.y + q.z * q.z);
        const yaw = std.math.atan2(siny_cosp, cosy_cosp);

        return rl.Vector3{ .x = roll, .y = pitch, .z = yaw };
    }

    /// Gets Euler angles (roll=X, pitch=Y, yaw=Z) in degrees
    pub fn getEulerDegrees(self: *const Transform) rl.Vector3 {
        const e = self.getEuler();
        const factor: f32 = 180.0 / @as(f32, std.math.pi);
        return rl.Vector3{ .x = e.x * factor, .y = e.y * factor, .z = e.z * factor };
    }

    /// Sets rotation from a quaternion, preserving position and scale
    pub fn setRotation(self: *Transform, q: rl.Quaternion) void {
        // Preserve scale and translation, replace rotation using quaternion->matrix formula
        var sx = std.math.sqrt(self.matrix.m0 * self.matrix.m0 + self.matrix.m1 * self.matrix.m1 + self.matrix.m2 * self.matrix.m2);
        var sy = std.math.sqrt(self.matrix.m4 * self.matrix.m4 + self.matrix.m5 * self.matrix.m5 + self.matrix.m6 * self.matrix.m6);
        var sz = std.math.sqrt(self.matrix.m8 * self.matrix.m8 + self.matrix.m9 * self.matrix.m9 + self.matrix.m10 * self.matrix.m10);
        const EPS: f32 = 1e-8;
        if (sx < EPS) sx = 1.0;
        if (sy < EPS) sy = 1.0;
        if (sz < EPS) sz = 1.0;

        const x = q.x;
        const y = q.y;
        const z = q.z;
        const w = q.w;
        const xx = x * x;
        const yy = y * y;
        const zz = z * z;
        const xy = x * y;
        const xz = x * z;
        const yz = y * z;
        const wx = w * x;
        const wy = w * y;
        const wz = w * z;

        // Row-major 3x3 rotation basis scaled by sx, sy, sz
        self.matrix.m0 = (1.0 - 2.0 * (yy + zz)) * sx;
        self.matrix.m1 = (2.0 * (xy + wz)) * sx;
        self.matrix.m2 = (2.0 * (xz - wy)) * sx;
        self.matrix.m3 = 0.0;

        self.matrix.m4 = (2.0 * (xy - wz)) * sy;
        self.matrix.m5 = (1.0 - 2.0 * (xx + zz)) * sy;
        self.matrix.m6 = (2.0 * (yz + wx)) * sy;
        self.matrix.m7 = 0.0;

        self.matrix.m8 = (2.0 * (xz + wy)) * sz;
        self.matrix.m9 = (2.0 * (yz - wx)) * sz;
        self.matrix.m10 = (1.0 - 2.0 * (xx + yy)) * sz;
        self.matrix.m11 = 0.0;
        // translation stays the same (m12..m14)
        self.matrix.m15 = 1.0;
    }

    /// Sets rotation from Euler angles (in radians), preserving position and scale
    pub fn setRotationFromEuler(self: *Transform, e: rl.Vector3) void {
        // rl.Quaternion.fromEuler takes (pitch, yaw, roll) in some versions; construct via matrix to be safe
        const m = rl.Matrix.rotateXYZ(e);
        const q = rl.Quaternion.fromMatrix(m);
        self.setRotation(q);
    }
};

/// Heuristic check whether a rotation vector is likely expressed in radians.
///
/// - Returns true if all components are within ~2π (+5% tolerance)
/// - Returns false if any component falls between ~2π and 360 (likely degrees)
/// - Returns true if any component > 360 (likely radians representing large rotations)
fn isRotationInRadians(v: rl.Vector3) bool {
    const rad_limit: f32 = @as(f32, std.math.pi * 2.0) * 1.05; // 2π + 5%
    const deg_limit: f32 = 360.0;
    const ax = if (v.x < 0.0) -v.x else v.x;
    const ay = if (v.y < 0.0) -v.y else v.y;
    const az = if (v.z < 0.0) -v.z else v.z;
    if (ax <= rad_limit and ay <= rad_limit and az <= rad_limit) return true;
    if ((ax > rad_limit and ax <= deg_limit) or (ay > rad_limit and ay <= deg_limit) or (az > rad_limit and az <= deg_limit)) return false;
    if (ax > deg_limit or ay > deg_limit or az > deg_limit) return true;
    return false;
}

test "Transform rotation vector units heuristics" {
    // small radians -> true
    try std.testing.expect(isRotationInRadians(rl.Vector3{ .x = 0.5, .y = 1.0, .z = -1.0 }));

    // typical degrees -> false
    try std.testing.expect(!isRotationInRadians(rl.Vector3{ .x = 180.0, .y = 0.0, .z = 45.0 }));

    // very large values -> likely radians (rotations beyond degrees range)
    try std.testing.expect(isRotationInRadians(rl.Vector3{ .x = 1000.0, .y = 0.0, .z = 0.0 }));
}
