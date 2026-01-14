const std = @import("std");
const rl = @import("raylib");
const common = @import("components.zig");
const zevy_ecs = @import("zevy_ecs");

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
        // Quaternions have a sign ambiguity (q and -q represent the same rotation).
        const dot = q.x * expected_q.x + q.y * expected_q.y + q.z * expected_q.z + q.w * expected_q.w;
        const sign: f32 = if (dot < 0.0) -1.0 else 1.0;
        const eqx = expected_q.x * sign;
        const eqy = expected_q.y * sign;
        const eqz = expected_q.z * sign;
        const eqw = expected_q.w * sign;
        const eps_q: f32 = 1e-4;
        std.debug.print("initFrom: q = {any}, {any}, {any}, {any}\n", .{ q.x, q.y, q.z, q.w });
        std.debug.print("initFrom: expected = {any}, {any}, {any}, {any}\n", .{ eqx, eqy, eqz, eqw });
        try std.testing.expect(q.x - eqx >= -eps_q and q.x - eqx <= eps_q);
        try std.testing.expect(q.y - eqy >= -eps_q and q.y - eqy <= eps_q);
        try std.testing.expect(q.z - eqz >= -eps_q and q.z - eqz <= eps_q);
        try std.testing.expect(q.w - eqw >= -eps_q and q.w - eqw <= eps_q);

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
