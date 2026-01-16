const std = @import("std");
const rl = @import("raylib");
const common = @import("components/transform.zig");
const zevy_ecs = @import("zevy_ecs");
const tutil = @import("test_utils.zig");

test "Transform init position is zero" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const e = manager.create(.{common.Transform.init()});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const pos = transform.getPosition();
        try std.testing.expectEqual(@as(f32, 0.0), pos.x);
        try std.testing.expectEqual(@as(f32, 0.0), pos.y);
        try std.testing.expectEqual(@as(f32, 0.0), pos.z);
    } else try std.testing.expect(false);
}

test "Transform translate updates position" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const e = manager.create(.{common.Transform.init()});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        transform.translate(rl.Vector3{ .x = 1.0, .y = 2.0, .z = 3.0 });
    } else try std.testing.expect(false);

    const updated = try manager.getComponent(e, common.Transform);
    if (updated) |transform| {
        const pos = transform.getPosition();
        try std.testing.expectEqual(@as(f32, 1.0), pos.x);
        try std.testing.expectEqual(@as(f32, 2.0), pos.y);
        try std.testing.expectEqual(@as(f32, 3.0), pos.z);
    } else try std.testing.expect(false);
}

test "initFromPosRotScale preserves translation and composes transforms" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = rl.Vector3{ .x = 5.0, .y = -3.0, .z = 2.0 };
    const rot = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const scale = rl.Vector3{ .x = 2.0, .y = 2.0, .z = 2.0 };

    const e = manager.create(.{common.Transform.initFromPosRotScale(pos, rot, scale)});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const p = transform.getPosition();
        try std.testing.expectEqual(@as(f32, 5.0), p.x);
        try std.testing.expectEqual(@as(f32, -3.0), p.y);
        try std.testing.expectEqual(@as(f32, 2.0), p.z);

        // Rotation should be identity for zero rotation
        const q = transform.getRotation();
        const expected_q = rl.Quaternion.fromMatrix(rl.Matrix.rotateXYZ(rot));
        const eps_q: f32 = tutil.DEFAULT_EPS;
        try tutil.expectQuatEqual(q, expected_q, eps_q);

        // Translate again to ensure composition works
        transform.translate(rl.Vector3{ .x = 1.0, .y = 1.0, .z = 1.0 });
        const p2 = transform.getPosition();
        try std.testing.expectEqual(@as(f32, 6.0), p2.x);
        try std.testing.expectEqual(@as(f32, -2.0), p2.y);
        try std.testing.expectEqual(@as(f32, 3.0), p2.z);
    } else try std.testing.expect(false);
}

test "Transform getRotation after rotate" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const e = manager.create(.{common.Transform.init()});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const rot = rl.Vector3{ .x = 0.3, .y = 0.5, .z = -0.2 };
        transform.rotate(rot);
        const q = transform.getRotation();
        const expected_q = rl.Quaternion.fromMatrix(rl.Matrix.rotateXYZ(rot));
        const dot = q.x * expected_q.x + q.y * expected_q.y + q.z * expected_q.z + q.w * expected_q.w;
        const sign: f32 = if (dot < 0.0) -1.0 else 1.0;
        const eqx = expected_q.x * sign;
        const eqy = expected_q.y * sign;
        const eqz = expected_q.z * sign;
        const eqw = expected_q.w * sign;
        const eps_q: f32 = 1e-4;
        std.debug.print("rotate: q = {any}, {any}, {any}, {any}\n", .{ q.x, q.y, q.z, q.w });
        std.debug.print("rotate: expected = {any}, {any}, {any}, {any}\n", .{ eqx, eqy, eqz, eqw });
        try std.testing.expect(q.x - eqx >= -eps_q and q.x - eqx <= eps_q);
        try std.testing.expect(q.y - eqy >= -eps_q and q.y - eqy <= eps_q);
        try std.testing.expect(q.z - eqz >= -eps_q and q.z - eqz <= eps_q);
        try std.testing.expect(q.w - eqw >= -eps_q and q.w - eqw <= eps_q);
    } else try std.testing.expect(false);
}

test "Transform setRotation preserves scale+translation" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = rl.Vector3{ .x = 1.0, .y = 2.0, .z = 3.0 };
    const rot = rl.Vector3{ .x = 0.4, .y = -0.2, .z = 0.9 };
    const scale = rl.Vector3{ .x = 2.0, .y = 3.0, .z = 4.0 };

    const e = manager.create(.{common.Transform.initFromPosRotScale(pos, rot, scale)});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const new_rot = rl.Vector3{ .x = -0.3, .y = 0.6, .z = 0.1 };
        const new_q = rl.Quaternion.fromMatrix(rl.Matrix.rotateXYZ(new_rot));
        transform.setRotation(new_q);

        // translation should remain unchanged
        const p = transform.getPosition();
        try std.testing.expectEqual(@as(f32, 1.0), p.x);
        try std.testing.expectEqual(@as(f32, 2.0), p.y);
        try std.testing.expectEqual(@as(f32, 3.0), p.z);

        // scale should remain approximately the same (derived from basis lengths)
        const sx = std.math.sqrt(transform.matrix.m0 * transform.matrix.m0 + transform.matrix.m1 * transform.matrix.m1 + transform.matrix.m2 * transform.matrix.m2);
        const sy = std.math.sqrt(transform.matrix.m4 * transform.matrix.m4 + transform.matrix.m5 * transform.matrix.m5 + transform.matrix.m6 * transform.matrix.m6);
        const sz = std.math.sqrt(transform.matrix.m8 * transform.matrix.m8 + transform.matrix.m9 * transform.matrix.m9 + transform.matrix.m10 * transform.matrix.m10);
        const eps_s: f32 = 1e-4;
        try std.testing.expect(sx - scale.x >= -eps_s and sx - scale.x <= eps_s);
        try std.testing.expect(sy - scale.y >= -eps_s and sy - scale.y <= eps_s);
        try std.testing.expect(sz - scale.z >= -eps_s and sz - scale.z <= eps_s);

        // rotation should match new_q (up to sign)
        const q = transform.getRotation();
        const dot = q.x * new_q.x + q.y * new_q.y + q.z * new_q.z + q.w * new_q.w;
        const sgn: f32 = if (dot < 0.0) -1.0 else 1.0;
        const eps_q: f32 = 1e-4;
        try std.testing.expect(q.x - new_q.x * sgn >= -eps_q and q.x - new_q.x * sgn <= eps_q);
        try std.testing.expect(q.y - new_q.y * sgn >= -eps_q and q.y - new_q.y * sgn <= eps_q);
        try std.testing.expect(q.z - new_q.z * sgn >= -eps_q and q.z - new_q.z * sgn <= eps_q);
        try std.testing.expect(q.w - new_q.w * sgn >= -eps_q and q.w - new_q.w * sgn <= eps_q);
    } else try std.testing.expect(false);
}

test "Transform getEuler returns rotation in radians" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const e = manager.create(.{common.Transform.init()});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const rot = rl.Vector3{ .x = 0.2, .y = -0.3, .z = 0.5 };
        transform.rotate(rot);
        const euler = transform.getEuler();
        // Compare rotation reconstructed from the returned Euler angles against expected quaternion
        const mat_from_euler = rl.Matrix.rotateXYZ(euler);
        const mat_expected = rl.Matrix.rotateXYZ(rot);
        // Reconstruct quaternions and compare via dot product to allow canonical differences
        const q_from_euler = rl.Quaternion.fromMatrix(mat_from_euler);
        const expected_q = rl.Quaternion.fromMatrix(mat_expected);
        const dot = q_from_euler.x * expected_q.x + q_from_euler.y * expected_q.y + q_from_euler.z * expected_q.z + q_from_euler.w * expected_q.w;
        std.debug.print("getEuler: dot = {any}\n", .{dot});
        std.debug.print("getEuler: q_from_euler = {any}, {any}, {any}, {any}\n", .{ q_from_euler.x, q_from_euler.y, q_from_euler.z, q_from_euler.w });
        std.debug.print("getEuler: expected = {any}, {any}, {any}, {any}\n", .{ expected_q.x, expected_q.y, expected_q.z, expected_q.w });
        const eps_dot: f32 = 5e-3; // allow tiny numerical/representation differences
        try std.testing.expect(dot >= 1.0 - eps_dot or dot <= -1.0 + eps_dot);
    } else try std.testing.expect(false);
}

test "Transform getEulerDegrees returns degrees" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const e = manager.create(.{common.Transform.init()});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const rot = rl.Vector3{ .x = 0.2, .y = -0.3, .z = 0.5 };
        transform.rotate(rot);
        const deg = transform.getEulerDegrees();
        const factor: f32 = 180.0 / @as(f32, std.math.pi);
        const rad = rl.Vector3{ .x = deg.x / factor, .y = deg.y / factor, .z = deg.z / factor };
        const mat_from_deg = rl.Matrix.rotateXYZ(rad);
        const mat_expected = rl.Matrix.rotateXYZ(rot);
        const q_from = rl.Quaternion.fromMatrix(mat_from_deg);
        const q_expected = rl.Quaternion.fromMatrix(mat_expected);
        const dot = q_from.x * q_expected.x + q_from.y * q_expected.y + q_from.z * q_expected.z + q_from.w * q_expected.w;
        const eps_dot: f32 = 5e-3;
        try std.testing.expect(dot >= 1.0 - eps_dot or dot <= -1.0 + eps_dot);
    } else try std.testing.expect(false);
}

test "Transform rotation with tolerance" {
    // radians within tolerance -> true
    try std.testing.expect(common.isRotationInRadians(rl.Vector3{ .x = 6.5, .y = 0.0, .z = 0.0 }, 1.1));

    // degrees within tolerance -> false
    try std.testing.expect(!common.isRotationInRadians(rl.Vector3{ .x = 350.0, .y = 0.0, .z = 0.0 }, 1.05));

    // large values beyond degrees range -> true
    try std.testing.expect(common.isRotationInRadians(rl.Vector3{ .x = 400.0, .y = 0.0, .z = 0.0 }, 1.0));
}

test "Transform rotateDegrees" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const e = manager.create(.{common.Transform.init()});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        // Avoid gimbal-singularity by not using 90° pitch
        const rot_deg = rl.Vector3{ .x = 45.0, .y = 90.0, .z = 180.0 };
        transform.rotateDegrees(rot_deg);
        const factor: f32 = @as(f32, std.math.pi) / 180.0;
        const expected_rad = rl.Vector3{ .x = rot_deg.x * factor, .y = rot_deg.y * factor, .z = rot_deg.z * factor };
        const mat_expected = rl.Matrix.rotateXYZ(expected_rad);
        const expected_q = rl.Quaternion.fromMatrix(mat_expected);
        const actual_q = transform.getRotation();
        const dot = actual_q.x * expected_q.x + actual_q.y * expected_q.y + actual_q.z * expected_q.z + actual_q.w * expected_q.w;
        const eps_dot: f32 = 5e-3;
        try std.testing.expect(dot >= 1.0 - eps_dot or dot <= -1.0 + eps_dot);
    } else try std.testing.expect(false);
}

test "Transform local/world and direction" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = rl.Vector3{ .x = 5.0, .y = -3.0, .z = 2.0 };
    const rot = rl.Vector3{ .x = 0.3, .y = 0.5, .z = -0.2 };
    const scale = rl.Vector3{ .x = 2.0, .y = 3.0, .z = 4.0 };

    const e = manager.create(.{common.Transform.initFromPosRotScale(pos, rot, scale)});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const local = rl.Vector3{ .x = 1.0, .y = 2.0, .z = -1.0 };
        const world = transform.toWorldPoint(local);
        const local_back = transform.toLocalPoint(world);
        const eps: f32 = tutil.DEFAULT_EPS;
        try tutil.expectVec3AlmostEqual(local_back, local, eps);

        // transformDirection should ignore translation
        const dir = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 1.0 };
        const world_dir = transform.transformDirection(dir);
        try std.testing.expect(!(world_dir.x == transform.getPosition().x and world_dir.y == transform.getPosition().y and world_dir.z == transform.getPosition().z));
    } else try std.testing.expect(false);
}

test "Transform rotateAround" {
    // rotate a point at (2,0,0) around pivot (1,0,0) by 90° about Z -> ends at (1,1,0)
    var t = common.Transform.initFromPosRotScale(rl.Vector3{ .x = 2.0, .y = 0.0, .z = 0.0 }, rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 }, rl.Vector3{ .x = 1.0, .y = 1.0, .z = 1.0 });
    t.rotateAround(rl.Vector3{ .x = 1.0, .y = 0.0, .z = 0.0 }, rl.Vector3{ .x = 0.0, .y = 0.0, .z = @as(f32, std.math.pi) / 2.0 });
    const p = t.getPosition();
    const eps: f32 = 1e-4;
    try std.testing.expect(p.x - 1.0 >= -eps and p.x - 1.0 <= eps);
    try std.testing.expect(p.y - 1.0 >= -eps and p.y - 1.0 <= eps);
    try std.testing.expect(p.z - 0.0 >= -eps and p.z - 0.0 <= eps);

    var t2 = common.Transform.initFromPosRotScale(rl.Vector3{ .x = 2.0, .y = 0.0, .z = 0.0 }, rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 }, rl.Vector3{ .x = 1.0, .y = 1.0, .z = 1.0 });
    t2.rotateAroundDegrees(rl.Vector3{ .x = 1.0, .y = 0.0, .z = 0.0 }, rl.Vector3{ .x = 0.0, .y = 0.0, .z = 90.0 });
    const p2 = t2.getPosition();
    try std.testing.expect(p2.x - 1.0 >= -eps and p2.x - 1.0 <= eps);
    try std.testing.expect(p2.y - 1.0 >= -eps and p2.y - 1.0 <= eps);
    try std.testing.expect(p2.z - 0.0 >= -eps and p2.z - 0.0 <= eps);
}

test "Transform toWorldPoint Vector4" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = rl.Vector3{ .x = 4.0, .y = -2.0, .z = 1.0 };
    const rot = rl.Vector3{ .x = 0.2, .y = 0.1, .z = -0.3 };
    const scale = rl.Vector3{ .x = 1.5, .y = 0.5, .z = 2.0 };

    const e = manager.create(.{common.Transform.initFromPosRotScale(pos, rot, scale)});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        // point (w = 1) should be same as toWorldPoint(Vector3)
        const local_point4 = rl.Vector4{ .x = 1.0, .y = 2.0, .z = -1.0, .w = 1.0 };
        const local_point3 = rl.Vector3{ .x = 1.0, .y = 2.0, .z = -1.0 };
        const world3 = transform.toWorldPoint(local_point3);
        const world4 = transform.toWorldPoint4(local_point4);
        const eps: f32 = tutil.DEFAULT_EPS;
        try tutil.expectVec3AlmostEqual(rl.Vector3{ .x = world4.x, .y = world4.y, .z = world4.z }, world3, eps);
        try std.testing.expect(world4.w == 1.0);

        // direction (w = 0) should match transformDirection and preserve w=0
        const local_dir4 = rl.Vector4{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 };
        const local_dir3 = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 1.0 };
        const world_dir3 = transform.transformDirection(local_dir3);
        const world_dir4 = transform.toWorldPoint4(local_dir4);
        try tutil.expectVec3AlmostEqual(rl.Vector3{ .x = world_dir4.x, .y = world_dir4.y, .z = world_dir4.z }, world_dir3, eps);
        try std.testing.expect(world_dir4.w == 0.0);

        // round-trip toLocalPoint4
        const local_rt = transform.toLocalPoint4(world4);
        try tutil.expectVec4AlmostEqual(local_rt, local_point4, eps);
    } else try std.testing.expect(false);
}

test "Transform getScale returns per-axis scales" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    // Use identity rotation so basis lengths equal the supplied scale vector
    const rot = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const scale = rl.Vector3{ .x = 2.0, .y = 3.0, .z = 4.0 };

    const e = manager.create(.{common.Transform.initFromPosRotScale(pos, rot, scale)});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const s = transform.getScale();
        const eps: f32 = tutil.DEFAULT_EPS;
        try tutil.expectVec3AlmostEqual(s, scale, eps);
    } else try std.testing.expect(false);
}

test "Transform scale preserves translation and multiplies basis" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = rl.Vector3{ .x = 1.0, .y = 2.0, .z = 3.0 };
    const rot = rl.Vector3{ .x = 0.2, .y = 0.1, .z = -0.3 };
    const scale0 = rl.Vector3{ .x = 1.5, .y = 0.5, .z = 2.0 };
    const scale1 = rl.Vector3{ .x = 2.0, .y = 3.0, .z = 0.5 };

    const e = manager.create(.{common.Transform.initFromPosRotScale(pos, rot, scale0)});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const s_before = transform.getScale();
        transform.scale(scale1);
        // position should be unchanged
        const p = transform.getPosition();
        try std.testing.expectEqual(p.x, pos.x);
        try std.testing.expectEqual(p.y, pos.y);
        try std.testing.expectEqual(p.z, pos.z);

        // scale should be multiplied element-wise by the applied local-scale factors
        const s = transform.getScale();
        const expected = rl.Vector3{ .x = s_before.x * scale1.x, .y = s_before.y * scale1.y, .z = s_before.z * scale1.z };
        const eps: f32 = tutil.DEFAULT_EPS;
        try tutil.expectVec3AlmostEqual(s, expected, eps);
    } else try std.testing.expect(false);
}

test "Transform setScale sets absolute scale and preserves rotation/translation" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = rl.Vector3{ .x = -1.0, .y = 0.5, .z = 2.0 };
    const rot = rl.Vector3{ .x = 0.3, .y = -0.4, .z = 0.2 };
    const scale0 = rl.Vector3{ .x = 1.0, .y = 1.0, .z = 1.0 };
    const target = rl.Vector3{ .x = 0.5, .y = 2.0, .z = 3.0 };

    const e = manager.create(.{common.Transform.initFromPosRotScale(pos, rot, scale0)});
    const t = try manager.getComponent(e, common.Transform);
    if (t) |transform| {
        const q_before = transform.getRotation();
        transform.setScale(target);
        const p_after = transform.getPosition();
        try std.testing.expectEqual(p_after.x, pos.x);
        try std.testing.expectEqual(p_after.y, pos.y);
        try std.testing.expectEqual(p_after.z, pos.z);

        const s_after = transform.getScale();
        const eps: f32 = tutil.DEFAULT_EPS;
        try tutil.expectVec3AlmostEqual(s_after, target, eps);

        const q_after = transform.getRotation();
        const dot = q_before.x * q_after.x + q_before.y * q_after.y + q_before.z * q_after.z + q_before.w * q_after.w;
        try std.testing.expect(dot >= 1.0 - 1e-3 or dot <= -1.0 + 1e-3);
    } else try std.testing.expect(false);
}
