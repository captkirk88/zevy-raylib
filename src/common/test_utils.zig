const std = @import("std");
const rl = @import("raylib");

/// Small test helper utilities for floating-point comparisons.
/// Keep functions tiny and re-exportable for test files.
pub const DEFAULT_EPS: f32 = 1e-4;

pub fn approxEqual(a: f32, b: f32, eps: f32) bool {
    const d = a - b;
    return d >= -eps and d <= eps;
}

pub fn expectAlmostEqual(a: f32, b: f32, eps: f32) anyerror!void {
    try std.testing.expect(approxEqual(a, b, eps));
}

pub fn expectAlmostEqualDefault(a: f32, b: f32) anyerror!void {
    try expectAlmostEqual(a, b, DEFAULT_EPS);
}

pub fn expectVec3AlmostEqual(a: rl.Vector3, b: rl.Vector3, eps: f32) anyerror!void {
    try expectAlmostEqual(a.x, b.x, eps);
    try expectAlmostEqual(a.y, b.y, eps);
    try expectAlmostEqual(a.z, b.z, eps);
}

pub fn expectVec4AlmostEqual(a: rl.Vector4, b: rl.Vector4, eps: f32) anyerror!void {
    try expectAlmostEqual(a.x, b.x, eps);
    try expectAlmostEqual(a.y, b.y, eps);
    try expectAlmostEqual(a.z, b.z, eps);
    try expectAlmostEqual(a.w, b.w, eps);
}

/// Compare two quaternions for rotational equivalence (q ~= ±expected)
pub fn expectQuatEqual(q: rl.Quaternion, expected: rl.Quaternion, eps: f32) anyerror!void {
    const dot = q.x * expected.x + q.y * expected.y + q.z * expected.z + q.w * expected.w;
    try std.testing.expect(dot >= 1.0 - eps or dot <= -1.0 + eps);
}
