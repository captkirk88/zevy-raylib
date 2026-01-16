//! WORK-IN-PROGRESS
//!
const std = @import("std");
const rl = @import("raylib");

/// Heuristic check whether a rotation vector is likely expressed in radians.
///
/// This performs a simple magnitude-based heuristic using a radius threshold built
/// from 2π (default 2π * 1.05). It is intended to catch when a caller accidentally
/// supplies degrees instead of radians.
///
/// Parameters:
/// - `v`: Euler angles vector to test.
/// - `tolerance`: Optional multiplier applied to 2π (default ≈1.05) to relax the "radians" limit.
///
/// Returns `true` when the vector's components are consistent with radians, `false` when
/// they look like degrees. This is a heuristic and may be incorrect for pathological values.
///
/// Behavior summary:
/// - Returns true if all components are within ~2π * tolerance.
/// - Returns false if any component is between ~2π * tolerance and 360.0 (likely degrees).
/// - Returns true if any component is greater than 360.0 (likely large radian values).
pub fn isRotationInRadians(v: rl.Vector3, tolerance: ?f32) bool {
    const rad_limit: f32 = @as(f32, std.math.pi * 2.0) * (tolerance orelse 1.05); // 2π + 5%
    const deg_limit: f32 = 360.0;
    const ax = if (v.x < 0.0) -v.x else v.x;
    const ay = if (v.y < 0.0) -v.y else v.y;
    const az = if (v.z < 0.0) -v.z else v.z;
    if (ax <= rad_limit and ay <= rad_limit and az <= rad_limit) return true;
    if ((ax > rad_limit and ax <= deg_limit) or (ay > rad_limit and ay <= deg_limit) or (az > rad_limit and az <= deg_limit)) return false;
    if (ax > deg_limit or ay > deg_limit or az > deg_limit) return true;
    return false;
}

/// A Transform component representing position, rotation, and scale in 3D space.
///
/// The `matrix` field stores an affine transformation (typically used to map local
/// coordinates into world space). Methods on this type mutate the matrix in place.
///
/// Conventions and notes:
/// - Rotation methods expect radians (unless there is an explicit "Degrees" variant).
/// - Many mutating methods post-multiply the matrix (e.g., `M = M * R`), which has the
///   semantic effect of applying the new operation in the transform's local space.
/// - The transform embeds scale in the matrix basis; methods that extract or set rotation
///   will strip/reapply scale as needed to avoid corrupting scale components.
pub const Transform = struct {
    matrix: rl.Matrix,

    /// Create an identity `Transform`.
    ///
    /// The returned transform has no translation, rotation, or scale (equivalent to
    /// `rl.Matrix.identity()`). Use this to initialize or reset a transform.
    pub fn init() Transform {
        return Transform{
            .matrix = rl.Matrix.identity(),
        };
    }

    /// Initialize a `Transform` from position, rotation and scale.
    ///
    /// Parameters:
    /// - `position`: Translation to set (world coordinates).
    /// - `rotation`: Euler angles in **radians**, applied in XYZ order.
    /// - `_scale`: Per-axis scale.
    ///
    /// The internal matrix is built by starting with the scale matrix, then applying
    /// the rotation, then applying the translation. Concretely this code performs
    /// `M = S * R * T` using the matrix multiplication order used by `rl.Matrix.multiply`.
    pub fn initFromPosRotScale(position: rl.Vector3, rotation: rl.Vector3, _scale: rl.Vector3) Transform {
        var transform = Transform{
            .matrix = rl.Matrix.scale(_scale.x, _scale.y, _scale.z),
        };
        transform.matrix = transform.matrix.multiply(rl.Matrix.rotateXYZ(rotation));
        transform.matrix = transform.matrix.multiply(rl.Matrix.translate(position.x, position.y, position.z));
        return transform;
    }

    /// Apply a rotation (Euler XYZ) to the transform.
    ///
    /// - `rotation` is an Euler vector expressed in **radians**.
    /// - A heuristic check is performed and the function will panic if the values look
    ///   like degrees to help catch common mistakes.
    /// - The rotation is applied in the transform's local space by post-multiplying
    ///   the rotation matrix into the current matrix (`M = M * R`).
    pub fn rotate(self: *Transform, rotation: rl.Vector3) void {
        if (isRotationInRadians(rotation, null) == false) std.debug.panic("rotation vector components appear to be in degrees, but radians are expected: {{ {d}, {d}, {d} }}\n", .{ rotation.x, rotation.y, rotation.z });
        self.matrix = self.matrix.multiply(.rotateXYZ(rotation));
    }

    /// Same as `rotate` but allows a custom tolerance multiplier for the radians heuristic.
    ///
    /// - `rotation` is an Euler vector in **radians**.
    /// - `tolerance` multiplies 2π when deciding whether the values are radians.
    ///   Use a value >1.0 to relax the check.
    /// - Will panic when the heuristic detects values that look like degrees.
    pub fn rotateEx(self: *Transform, rotation: rl.Vector3, tolerance: f32) void {
        if (isRotationInRadians(rotation, tolerance) == false) std.debug.panic("rotation vector components appear to be in degrees, but radians are expected: {{ {d}, {d}, {d} }}\n", .{ rotation.x, rotation.y, rotation.z });
        self.matrix = self.matrix.multiply(rl.Matrix.rotateXYZ(rotation));
    }

    /// Apply a rotation specified in degrees.
    ///
    /// This converts degrees → radians using `π / 180` and then behaves like `rotate`,
    /// post-multiplying the rotation into the current matrix (local-space rotation).
    pub fn rotateDegrees(self: *Transform, rotation_deg: rl.Vector3) void {
        const factor: f32 = @as(f32, std.math.pi) / 180.0;
        const rotation_rad = rl.Vector3{
            .x = rotation_deg.x * factor,
            .y = rotation_deg.y * factor,
            .z = rotation_deg.z * factor,
        };
        self.matrix = self.matrix.multiply(rl.Matrix.rotateXYZ(rotation_rad));
    }

    /// Apply a translation to the transform.
    ///
    /// The translation is applied in the transform's local space by post-multiplying
    /// a translation matrix into the current matrix (`M = M * T`). This shifts local
    /// coordinates before the existing transform is applied.
    pub fn translate(self: *Transform, translation: rl.Vector3) void {
        self.matrix = self.matrix.multiply(rl.Matrix.translate(translation.x, translation.y, translation.z));
    }

    /// Transform a point from local space into world space using the full affine matrix.
    ///
    /// This applies rotation, scale and translation to `local` and returns the resulting
    /// world-space position. For pure directions use `transformDirection` which omits
    /// the translation term.
    pub fn toWorldPoint(self: *const Transform, local: rl.Vector3) rl.Vector3 {
        const m = self.matrix;
        return rl.Vector3{
            .x = m.m0 * local.x + m.m4 * local.y + m.m8 * local.z + m.m12,
            .y = m.m1 * local.x + m.m5 * local.y + m.m9 * local.z + m.m13,
            .z = m.m2 * local.x + m.m6 * local.y + m.m10 * local.z + m.m14,
        };
    }

    /// Transform a direction/vector (ignoring translation) from local into world space.
    ///
    /// This uses only the 3×3 rotation/scale basis of the matrix (translation ignored).
    /// Use this for transforming normals, velocities, and other direction-like vectors.
    pub fn transformDirection(self: *const Transform, local_dir: rl.Vector3) rl.Vector3 {
        const m = self.matrix;
        return rl.Vector3{
            .x = m.m0 * local_dir.x + m.m4 * local_dir.y + m.m8 * local_dir.z,
            .y = m.m1 * local_dir.x + m.m5 * local_dir.y + m.m9 * local_dir.z,
            .z = m.m2 * local_dir.x + m.m6 * local_dir.y + m.m10 * local_dir.z,
        };
    }

    /// Transform a point from world space into local space (affine inverse).
    ///
    /// The function computes the inverse of the 3×3 basis (rotation/scale) and then
    /// applies it to `(world - translation)`. If the basis matrix is degenerate
    /// (determinant near zero) the implementation falls back to using the identity
    /// basis so that the translation is simply subtracted.
    ///
    /// Notes:
    /// - Uses an epsilon (`1e-8`) to detect degeneracy and avoid numerical instability.
    pub fn toLocalPoint(self: *const Transform, world: rl.Vector3) rl.Vector3 {
        const m = self.matrix;
        // 3x3 basis matrix (columns)
        const b0x = m.m0;
        const b0y = m.m1;
        const b0z = m.m2;
        const b1x = m.m4;
        const b1y = m.m5;
        const b1z = m.m6;
        const b2x = m.m8;
        const b2y = m.m9;
        const b2z = m.m10;

        // Compute inverse of 3x3 basis (adjugate / det)
        const det = b0x * (b1y * b2z - b1z * b2y) - b1x * (b0y * b2z - b0z * b2y) + b2x * (b0y * b1z - b0z * b1y);
        // If degenerate, fall back to identity
        const EPS: f32 = 1e-8;
        var inv0x: f32 = 0.0;
        var inv0y: f32 = 0.0;
        var inv0z: f32 = 0.0;
        var inv1x: f32 = 0.0;
        var inv1y: f32 = 0.0;
        var inv1z: f32 = 0.0;
        var inv2x: f32 = 0.0;
        var inv2y: f32 = 0.0;
        var inv2z: f32 = 0.0;
        if (det > EPS or det < -EPS) {
            const invdet = 1.0 / det;
            inv0x = (b1y * b2z - b1z * b2y) * invdet;
            inv0y = -(b0y * b2z - b0z * b2y) * invdet;
            inv0z = (b0y * b1z - b0z * b1y) * invdet;

            inv1x = -(b1x * b2z - b1z * b2x) * invdet;
            inv1y = (b0x * b2z - b0z * b2x) * invdet;
            inv1z = -(b0x * b1z - b0z * b1x) * invdet;

            inv2x = (b1x * b2y - b1y * b2x) * invdet;
            inv2y = -(b0x * b2y - b0y * b2x) * invdet;
            inv2z = (b0x * b1y - b0y * b1x) * invdet;
        } else {
            inv0x = 1.0;
            inv0y = 0.0;
            inv0z = 0.0;
            inv1x = 0.0;
            inv1y = 1.0;
            inv1z = 0.0;
            inv2x = 0.0;
            inv2y = 0.0;
            inv2z = 1.0;
        }

        const tx = world.x - m.m12;
        const ty = world.y - m.m13;
        const tz = world.z - m.m14;

        return rl.Vector3{
            .x = inv0x * tx + inv1x * ty + inv2x * tz,
            .y = inv0y * tx + inv1y * ty + inv2y * tz,
            .z = inv0z * tx + inv1z * ty + inv2z * tz,
        };
    }

    /// Transform a homogeneous coordinate (Vector4) from local into world space.
    ///
    /// `local.w` determines whether the vector represents a position (`w = 1`) or a
    /// direction (`w = 0`). All components, including `w`, are transformed by the matrix
    /// (so `w` is useful for projecting homogeneous transforms through the matrix).
    pub fn toWorldPoint4(self: *const Transform, local: rl.Vector4) rl.Vector4 {
        const m = self.matrix;
        return rl.Vector4{
            .x = m.m0 * local.x + m.m4 * local.y + m.m8 * local.z + m.m12 * local.w,
            .y = m.m1 * local.x + m.m5 * local.y + m.m9 * local.z + m.m13 * local.w,
            .z = m.m2 * local.x + m.m6 * local.y + m.m10 * local.z + m.m14 * local.w,
            .w = m.m3 * local.x + m.m7 * local.y + m.m11 * local.z + m.m15 * local.w,
        };
    }

    /// Transform a homogeneous coordinate (Vector4) from world into local space.
    ///
    /// Handles the homogeneous `w` component correctly. The formula applied is:
    /// `local.xyz = R^{-1} * (world.xyz - t * world.w)` and the `w` component is preserved
    /// in the returned vector. If the basis is degenerate the implementation falls back to
    /// using the identity basis (as in `toLocalPoint`).
    pub fn toLocalPoint4(self: *const Transform, world: rl.Vector4) rl.Vector4 {
        const m = self.matrix;
        // 3x3 basis matrix (columns)
        const b0x = m.m0;
        const b0y = m.m1;
        const b0z = m.m2;
        const b1x = m.m4;
        const b1y = m.m5;
        const b1z = m.m6;
        const b2x = m.m8;
        const b2y = m.m9;
        const b2z = m.m10;

        const det = b0x * (b1y * b2z - b1z * b2y) - b1x * (b0y * b2z - b0z * b2y) + b2x * (b0y * b1z - b0z * b1y);
        const EPS: f32 = 1e-8;
        var inv0x: f32 = 0.0;
        var inv0y: f32 = 0.0;
        var inv0z: f32 = 0.0;
        var inv1x: f32 = 0.0;
        var inv1y: f32 = 0.0;
        var inv1z: f32 = 0.0;
        var inv2x: f32 = 0.0;
        var inv2y: f32 = 0.0;
        var inv2z: f32 = 0.0;
        if (det > EPS or det < -EPS) {
            const invdet = 1.0 / det;
            inv0x = (b1y * b2z - b1z * b2y) * invdet;
            inv0y = -(b0y * b2z - b0z * b2y) * invdet;
            inv0z = (b0y * b1z - b0z * b1y) * invdet;

            inv1x = -(b1x * b2z - b1z * b2x) * invdet;
            inv1y = (b0x * b2z - b0z * b2x) * invdet;
            inv1z = -(b0x * b1z - b0z * b1x) * invdet;

            inv2x = (b1x * b2y - b1y * b2x) * invdet;
            inv2y = -(b0x * b2y - b0y * b2x) * invdet;
            inv2z = (b0x * b1y - b0y * b1x) * invdet;
        } else {
            inv0x = 1.0;
            inv0y = 0.0;
            inv0z = 0.0;
            inv1x = 0.0;
            inv1y = 1.0;
            inv1z = 0.0;
            inv2x = 0.0;
            inv2y = 0.0;
            inv2z = 1.0;
        }

        // For homogeneous coords: local.xyz = R^{-1} * (world.xyz - t * world.w)
        const tx = world.x - m.m12 * world.w;
        const ty = world.y - m.m13 * world.w;
        const tz = world.z - m.m14 * world.w;

        return rl.Vector4{
            .x = inv0x * tx + inv1x * ty + inv2x * tz,
            .y = inv0y * tx + inv1y * ty + inv2y * tz,
            .z = inv0z * tx + inv1z * ty + inv2z * tz,
            .w = world.w,
        };
    }

    /// Rotate the transform around an arbitrary pivot point (Euler XYZ, radians).
    ///
    /// The pivot is specified in world coordinates. The operation performed is:
    /// `M' = T(pivot) * R * T(-pivot) * M` which rotates the existing transform
    /// around `pivot` in world space. This is equivalent to translating the transform
    /// so the pivot is at the origin, rotating, then translating back and applying
    /// the result to the current matrix.
    pub fn rotateAround(self: *Transform, pivot: rl.Vector3, rotation: rl.Vector3) void {
        const to_pivot = rl.Matrix.translate(pivot.x, pivot.y, pivot.z);
        const r = rl.Matrix.rotateXYZ(rotation);
        const from_pivot = rl.Matrix.translate(-pivot.x, -pivot.y, -pivot.z);
        // New matrix = T(pivot) * R * T(-pivot) * M
        const op = to_pivot.multiply(r).multiply(from_pivot);
        self.matrix = op.multiply(self.matrix);
    }

    /// Rotate the transform around a pivot using degrees.
    ///
    /// Converts degrees → radians and then performs `rotateAround` (pivot in world space).
    pub fn rotateAroundDegrees(self: *Transform, pivot: rl.Vector3, rotation_deg: rl.Vector3) void {
        const factor: f32 = @as(f32, std.math.pi) / 180.0;
        const rotation_rad = rl.Vector3{ .x = rotation_deg.x * factor, .y = rotation_deg.y * factor, .z = rotation_deg.z * factor };
        self.rotateAround(pivot, rotation_rad);
    }

    /// Apply a per-axis scale to the transform.
    ///
    /// The scale is applied in local space by post-multiplying a scale matrix
    /// into the current matrix (`M = M * S`). Scale values near zero may make
    /// subsequent rotation extraction numerically unstable.
    pub fn scale(self: *Transform, _scale: rl.Vector3) void {
        // Scale the basis columns directly so scaling is applied along the
        // transform's local axes (columns), which avoids ambiguity from
        // matrix-multiplication ordering semantics.
        self.matrix.m0 *= _scale.x;
        self.matrix.m1 *= _scale.x;
        self.matrix.m2 *= _scale.x;

        self.matrix.m4 *= _scale.y;
        self.matrix.m5 *= _scale.y;
        self.matrix.m6 *= _scale.y;

        self.matrix.m8 *= _scale.z;
        self.matrix.m9 *= _scale.z;
        self.matrix.m10 *= _scale.z;
    }

    /// Get the per-axis scale encoded in the transform matrix.
    ///
    /// Returns the lengths of the three basis column vectors (X, Y, Z).
    /// Note: If a basis vector is degenerate (near zero length), a very small
    /// value may be returned; users should treat extremely small scales as
    /// potentially ill-conditioned.
    pub fn getScale(self: *const Transform) rl.Vector3 {
        const m = self.matrix;
        return rl.Vector3{
            .x = std.math.sqrt(m.m0 * m.m0 + m.m1 * m.m1 + m.m2 * m.m2),
            .y = std.math.sqrt(m.m4 * m.m4 + m.m5 * m.m5 + m.m6 * m.m6),
            .z = std.math.sqrt(m.m8 * m.m8 + m.m9 * m.m9 + m.m10 * m.m10),
        };
    }

    /// Set per-axis scale while preserving rotation and translation.
    ///
    /// The implementation computes the current per-axis scale, derives relative
    /// scale factors (target / current) and post-multiplies the matrix by that
    /// scale so that existing rotation is preserved. If a current scale component
    /// is extremely small (EPS = 1e-8) it is treated as `1.0` to avoid division by
    /// zero; in such degenerate cases `setScale` may be unable to reconstruct a
    /// perfectly well-conditioned basis, but it still attempts to apply the
    /// requested scale factors.
    pub fn setScale(self: *Transform, target: rl.Vector3) void {
        const cur = self.getScale();
        const EPS: f32 = 1e-8;
        const sx = if (cur.x < EPS) target.x else target.x / cur.x;
        const sy = if (cur.y < EPS) target.y else target.y / cur.y;
        const sz = if (cur.z < EPS) target.z else target.z / cur.z;
        // Apply relative scale factors directly to the basis columns so that
        // the resulting basis lengths match the desired per-axis targets.
        self.matrix.m0 *= sx; self.matrix.m1 *= sx; self.matrix.m2 *= sx;
        self.matrix.m4 *= sy; self.matrix.m5 *= sy; self.matrix.m6 *= sy;
        self.matrix.m8 *= sz; self.matrix.m9 *= sz; self.matrix.m10 *= sz;
    }

    /// Set the translation component of the transform.
    ///
    /// This overwrites the matrix's translation elements (m12, m13, m14) and leaves
    /// rotation/scale untouched.
    pub fn setPosition(self: *Transform, position: rl.Vector3) void {
        self.matrix.m12 = position.x;
        self.matrix.m13 = position.y;
        self.matrix.m14 = position.z;
    }

    /// Get the translation component of the transform.
    ///
    /// Returns the vector stored in matrix elements (m12, m13, m14).
    pub fn getPosition(self: *const Transform) rl.Vector3 {
        return rl.Vector3{
            .x = self.matrix.m12,
            .y = self.matrix.m13,
            .z = self.matrix.m14,
        };
    }

    /// Extract the rotation component as a quaternion.
    ///
    /// The method strips out per-axis scale before building a pure rotation matrix and
    /// converts it to a quaternion using `rl.Quaternion.fromMatrix`.
    /// Small scale magnitudes are clamped to 1.0 (EPS = 1e-8) to avoid division by
    /// zero or numerical instability.
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
        return .fromMatrix(rot_m);
    }

    /// Get Euler angles (roll = X, pitch = Y, yaw = Z) in radians.
    ///
    /// Converts the transform's quaternion rotation into Euler angles using the
    /// standard conversion (roll, pitch, yaw). Pitch is clamped to ±π/2 to handle
    /// gimbal-limit cases when the conversion's sine argument slightly exceeds [-1,1].
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

    /// Get Euler angles in degrees.
    ///
    /// Equivalent to `getEuler()` but converted from radians to degrees.
    pub fn getEulerDegrees(self: *const Transform) rl.Vector3 {
        const e = self.getEuler();
        const factor: f32 = 180.0 / @as(f32, std.math.pi);
        return rl.Vector3{ .x = e.x * factor, .y = e.y * factor, .z = e.z * factor };
    }

    /// Set rotation from a quaternion while preserving scale and translation.
    ///
    /// This replaces the 3×3 rotation basis of the matrix with the quaternion's
    /// rotation, re-applying the existing per-axis scale so that scale and translation
    /// remain unchanged. Small scale values are clamped to 1.0 (EPS = 1e-8) to avoid
    /// numerical problems.
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

    /// Set rotation from Euler angles (in radians), preserving position and scale.
    ///
    /// This constructs a rotation matrix using `rotateXYZ` and converts it to a
    /// quaternion before applying with `setRotation`.
    pub fn setRotationFromEuler(self: *Transform, e: rl.Vector3) void {
        if (isRotationInRadians(e, null) == false) std.debug.panic("rotation vector components appear to be in degrees, but radians are expected: {{ {d}, {d}, {d} }}\n", .{ e.x, e.y, e.z });
        // rl.Quaternion.fromEuler takes (pitch, yaw, roll) in some versions; construct via matrix to be safe
        const m = rl.Matrix.rotateXYZ(e);
        const q = rl.Quaternion.fromMatrix(m);
        self.setRotation(q);
    }
};
