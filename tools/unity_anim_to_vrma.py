#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import json
import math
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

Vec3 = Tuple[float, float, float]
Quat = Tuple[float, float, float, float]  # x, y, z, w


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _v_add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _v_sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _v_dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _v_cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _v_len(a: Vec3) -> float:
    return math.sqrt(_v_dot(a, a))


def _v_norm(a: Vec3) -> Vec3:
    l = _v_len(a)
    if l <= 1e-12:
        return (0.0, 0.0, 0.0)
    return (a[0] / l, a[1] / l, a[2] / l)


def _q_mul(a: Quat, b: Quat) -> Quat:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def _q_conj(q: Quat) -> Quat:
    x, y, z, w = q
    return (-x, -y, -z, w)


def _q_norm(q: Quat) -> Quat:
    x, y, z, w = q
    l = math.sqrt(x * x + y * y + z * z + w * w)
    if l <= 1e-12:
        return (0.0, 0.0, 0.0, 1.0)
    return (x / l, y / l, z / l, w / l)


def _q_inv(q: Quat) -> Quat:
    return _q_conj(_q_norm(q))


def _q_dot(a: Quat, b: Quat) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]


def _q_rotate(q: Quat, v: Vec3) -> Vec3:
    vx, vy, vz = v
    vq: Quat = (vx, vy, vz, 0.0)
    rq = _q_mul(_q_mul(q, vq), _q_conj(q))
    return (rq[0], rq[1], rq[2])


def _q_axis_angle(axis: Vec3, angle_rad: float) -> Quat:
    axis_n = _v_norm(axis)
    if _v_len(axis_n) <= 1e-12:
        return (0.0, 0.0, 0.0, 1.0)
    s = math.sin(angle_rad * 0.5)
    return _q_norm(
        (axis_n[0] * s, axis_n[1] * s, axis_n[2] * s, math.cos(angle_rad * 0.5))
    )


def _unity_vec_to_gltf(v: Vec3) -> Vec3:
    # Unity (left-handed, +Z forward) -> glTF (right-handed, +Z forward)
    # by flipping the Z axis.
    return (float(v[0]), float(v[1]), -float(v[2]))


def _unity_quat_to_gltf(q: Quat) -> Quat:
    # Unity (left-handed, +Z forward) -> glTF (right-handed, +Z forward)
    # by flipping the Z axis: q' = (-x, -y, z, w)
    x, y, z, w = q
    return _q_norm((-float(x), -float(y), float(z), float(w)))


def _deg(degrees: float) -> float:
    return degrees * math.pi / 180.0


def _read_glb_json(path: Path) -> Dict[str, Any]:
    data = path.read_bytes()
    if len(data) < 12:
        raise ValueError(f"Invalid GLB: too small ({path})")
    magic, version, total_len = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        raise ValueError(f"Invalid GLB header ({path}): magic={magic} version={version}")
    if total_len != len(data):
        raise ValueError(f"Invalid GLB length ({path}): header={total_len} actual={len(data)}")
    off = 12
    json_chunk = None
    while off < total_len:
        if off + 8 > total_len:
            break
        chunk_len, chunk_type = struct.unpack_from("<I4s", data, off)
        off += 8
        chunk_data = data[off : off + chunk_len]
        off += chunk_len
        if chunk_type == b"JSON":
            json_chunk = chunk_data
    if json_chunk is None:
        raise ValueError(f"GLB missing JSON chunk: {path}")
    return json.loads(json_chunk.decode("utf-8"))


def _write_glb(path: Path, gltf: Dict[str, Any], bin_blob: bytes) -> None:
    json_bytes = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "
    bin_bytes = bytearray(bin_blob)
    while len(bin_bytes) % 4 != 0:
        bin_bytes.append(0)

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    header = struct.pack("<4sII", b"glTF", 2, total_len)
    json_header = struct.pack("<I4s", len(json_bytes), b"JSON")
    bin_header = struct.pack("<I4s", len(bin_bytes), b"BIN\x00")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + json_header + json_bytes + bin_header + bytes(bin_bytes))


def _parse_unity_anim_float_curves(anim_path: Path) -> Dict[str, List[Tuple[float, float]]]:
    import re

    lines = anim_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    re_float_start = re.compile(r"^\s*m_FloatCurves:\s*$")
    re_entry_start = re.compile(r"^\s{2}-\s+serializedVersion:\s*\d+\s*$")
    re_attr = re.compile(r"^\s*attribute:\s*(.+?)\s*$")
    re_time = re.compile(r"^\s*time:\s*([-0-9.eE]+)\s*$")
    re_value = re.compile(r"^\s*value:\s*([-0-9.eE]+)\s*$")

    curves: Dict[str, List[Tuple[float, float]]] = {}
    in_float = False
    entry: Optional[Dict[str, Any]] = None
    pending_time: Optional[float] = None

    def commit(e: Dict[str, Any]) -> None:
        attr = e.get("attribute")
        if not attr or str(attr).isdigit():
            return
        keys: List[Tuple[float, float]] = list(e.get("keys") or [])
        if not keys:
            return
        keys.sort(key=lambda kv: kv[0])
        curves[attr] = keys

    for line in lines:
        if not in_float:
            if re_float_start.match(line):
                in_float = True
            continue
        if line.startswith("  m_PPtrCurves:"):
            break

        if re_entry_start.match(line):
            if entry is not None:
                commit(entry)
            entry = {"attribute": None, "keys": []}
            pending_time = None
            continue
        if entry is None:
            continue

        m = re_attr.match(line)
        if m:
            entry["attribute"] = m.group(1)
            continue
        m = re_time.match(line)
        if m:
            pending_time = float(m.group(1))
            continue
        m = re_value.match(line)
        if m and pending_time is not None:
            entry["keys"].append((pending_time, float(m.group(1))))
            pending_time = None
            continue

    if entry is not None:
        commit(entry)
    return curves


def _curve_duration(curves: Dict[str, List[Tuple[float, float]]]) -> float:
    end = 0.0
    for keys in curves.values():
        if keys:
            end = max(end, keys[-1][0])
    return float(end)


def _sample_curve(keys: Optional[Sequence[Tuple[float, float]]], times: Sequence[float], default: float) -> List[float]:
    if not keys:
        return [default] * len(times)
    ks = list(keys)
    ks.sort(key=lambda kv: kv[0])
    out: List[float] = []
    i = 0
    for t in times:
        while i + 1 < len(ks) and t > ks[i + 1][0]:
            i += 1
        if i + 1 >= len(ks):
            out.append(float(ks[-1][1]))
            continue
        t0, v0 = ks[i]
        t1, v1 = ks[i + 1]
        if t1 <= t0 + 1e-12:
            out.append(float(v1))
            continue
        a = (t - t0) / (t1 - t0)
        out.append(float(v0 + (v1 - v0) * a))
    return out


@dataclass(frozen=True)
class HumanoidPose:
    world_pos: Dict[str, Vec3]
    world_rot: Dict[str, Quat]


def _compute_world_transforms(gltf: Dict[str, Any]) -> Tuple[List[int], List[Vec3], List[Quat]]:
    nodes: List[Dict[str, Any]] = gltf.get("nodes") or []
    parents = [-1] * len(nodes)
    for idx, node in enumerate(nodes):
        for ch in node.get("children", []) or []:
            if 0 <= ch < len(nodes):
                parents[ch] = idx

    world_pos: List[Optional[Vec3]] = [None] * len(nodes)
    world_rot: List[Optional[Quat]] = [None] * len(nodes)

    def local_pos(i: int) -> Vec3:
        t = nodes[i].get("translation") or [0.0, 0.0, 0.0]
        return (float(t[0]), float(t[1]), float(t[2]))

    def local_rot(i: int) -> Quat:
        r = nodes[i].get("rotation") or [0.0, 0.0, 0.0, 1.0]
        return _q_norm((float(r[0]), float(r[1]), float(r[2]), float(r[3])))

    def compute(i: int) -> Tuple[Vec3, Quat]:
        if world_pos[i] is not None and world_rot[i] is not None:
            return world_pos[i], world_rot[i]
        p = parents[i]
        lp = local_pos(i)
        lr = local_rot(i)
        if p == -1:
            wp = lp
            wr = lr
        else:
            pp, pr = compute(p)
            wp = _v_add(pp, _q_rotate(pr, lp))
            wr = _q_mul(pr, lr)
        world_pos[i] = wp
        world_rot[i] = wr
        return wp, wr

    scene_index = gltf.get("scene", 0)
    scenes = gltf.get("scenes") or []
    if 0 <= scene_index < len(scenes):
        for r in scenes[scene_index].get("nodes", []) or []:
            if 0 <= r < len(nodes):
                compute(r)
    for i in range(len(nodes)):
        compute(i)

    return parents, [p for p in world_pos if p is not None], [q for q in world_rot if q is not None]


def _load_template_humanoid_pose(template_vrm: Path) -> Tuple[HumanoidPose, List[str]]:
    gltf = _read_glb_json(template_vrm)
    vrm = (gltf.get("extensions") or {}).get("VRMC_vrm") or {}
    bone_items = ((vrm.get("humanoid") or {}).get("humanBones") or {}).items()
    if not bone_items:
        raise ValueError(f"Template has no VRMC_vrm.humanoid.humanBones: {template_vrm}")

    _, world_pos_all, world_rot_all = _compute_world_transforms(gltf)
    nodes = gltf.get("nodes") or []

    world_pos: Dict[str, Vec3] = {}
    world_rot: Dict[str, Quat] = {}
    present: List[str] = []
    for name, entry in bone_items:
        node_index = int((entry or {}).get("node", -1))
        if not (0 <= node_index < len(nodes)):
            continue
        world_pos[name] = world_pos_all[node_index]
        world_rot[name] = world_rot_all[node_index]
        present.append(name)

    return HumanoidPose(world_pos=world_pos, world_rot=world_rot), present


VRM_PARENT: Dict[str, Optional[str]] = {
    "hips": None,
    "spine": "hips",
    "chest": "spine",
    "upperChest": "chest",
    "neck": "upperChest",
    "head": "neck",
    "jaw": "head",
    "leftEye": "head",
    "rightEye": "head",
    "leftShoulder": "upperChest",
    "leftUpperArm": "leftShoulder",
    "leftLowerArm": "leftUpperArm",
    "leftHand": "leftLowerArm",
    "rightShoulder": "upperChest",
    "rightUpperArm": "rightShoulder",
    "rightLowerArm": "rightUpperArm",
    "rightHand": "rightLowerArm",
    "leftUpperLeg": "hips",
    "leftLowerLeg": "leftUpperLeg",
    "leftFoot": "leftLowerLeg",
    "leftToes": "leftFoot",
    "rightUpperLeg": "hips",
    "rightLowerLeg": "rightUpperLeg",
    "rightFoot": "rightLowerLeg",
    "rightToes": "rightFoot",
    # Left hand fingers
    "leftThumbMetacarpal": "leftHand",
    "leftThumbProximal": "leftThumbMetacarpal",
    "leftThumbDistal": "leftThumbProximal",
    "leftIndexProximal": "leftHand",
    "leftIndexIntermediate": "leftIndexProximal",
    "leftIndexDistal": "leftIndexIntermediate",
    "leftMiddleProximal": "leftHand",
    "leftMiddleIntermediate": "leftMiddleProximal",
    "leftMiddleDistal": "leftMiddleIntermediate",
    "leftRingProximal": "leftHand",
    "leftRingIntermediate": "leftRingProximal",
    "leftRingDistal": "leftRingIntermediate",
    "leftLittleProximal": "leftHand",
    "leftLittleIntermediate": "leftLittleProximal",
    "leftLittleDistal": "leftLittleIntermediate",
    # Right hand fingers
    "rightThumbMetacarpal": "rightHand",
    "rightThumbProximal": "rightThumbMetacarpal",
    "rightThumbDistal": "rightThumbProximal",
    "rightIndexProximal": "rightHand",
    "rightIndexIntermediate": "rightIndexProximal",
    "rightIndexDistal": "rightIndexIntermediate",
    "rightMiddleProximal": "rightHand",
    "rightMiddleIntermediate": "rightMiddleProximal",
    "rightMiddleDistal": "rightMiddleIntermediate",
    "rightRingProximal": "rightHand",
    "rightRingIntermediate": "rightRingProximal",
    "rightRingDistal": "rightRingIntermediate",
    "rightLittleProximal": "rightHand",
    "rightLittleIntermediate": "rightLittleProximal",
    "rightLittleDistal": "rightLittleIntermediate",
}


def _resolve_parent(bone: str, present: set[str]) -> Optional[str]:
    p = VRM_PARENT.get(bone)
    while p is not None and p not in present:
        p = VRM_PARENT.get(p)
    return p


def _build_vrma_skeleton(
    pose: HumanoidPose, present_bones: Sequence[str]
) -> Tuple[List[Dict[str, Any]], Dict[str, int], Dict[str, Optional[str]]]:
    present = set(present_bones)
    parents: Dict[str, Optional[str]] = {b: _resolve_parent(b, present) for b in present_bones}
    children: Dict[str, List[str]] = {b: [] for b in present_bones}
    roots: List[str] = []
    for b in present_bones:
        p = parents[b]
        if p is None:
            roots.append(b)
        else:
            children[p].append(b)

    for k in children:
        children[k].sort()
    roots.sort()

    order: List[str] = []

    def dfs(b: str) -> None:
        order.append(b)
        for ch in children.get(b, []):
            dfs(ch)

    for r in roots:
        dfs(r)

    index: Dict[str, int] = {}
    nodes: List[Dict[str, Any]] = []

    for b in order:
        p = parents[b]
        wp = pose.world_pos[b]
        wr = pose.world_rot[b]
        if p is None:
            lp = wp
            lr = wr
        else:
            pp = pose.world_pos[p]
            pr = pose.world_rot[p]
            inv_pr = _q_inv(pr)
            lp = _q_rotate(inv_pr, _v_sub(wp, pp))
            lr = _q_mul(inv_pr, wr)
        index[b] = len(nodes)
        nodes.append(
            {
                "name": b,
                "translation": [lp[0], lp[1], lp[2]],
                "rotation": [lr[0], lr[1], lr[2], lr[3]],
            }
        )

    # Add children arrays.
    for b in order:
        p = parents[b]
        if p is None:
            continue
        nodes[index[p]].setdefault("children", []).append(index[b])
    for node in nodes:
        if "children" in node:
            node["children"].sort()

    return nodes, index, parents


WORLD_UP: Vec3 = (0.0, 1.0, 0.0)
WORLD_RIGHT: Vec3 = (1.0, 0.0, 0.0)
WORLD_FWD: Vec3 = (0.0, 0.0, 1.0)
WORLD_BACK: Vec3 = (0.0, 0.0, -1.0)
WORLD_DOWN: Vec3 = (0.0, -1.0, 0.0)


def _bone_dir_world(pose: HumanoidPose, parents: Dict[str, Optional[str]], bone: str) -> Vec3:
    child_hint: Dict[str, str] = {
        "hips": "spine",
        "spine": "chest",
        "chest": "upperChest",
        "upperChest": "neck",
        "neck": "head",
        "leftShoulder": "leftUpperArm",
        "leftUpperArm": "leftLowerArm",
        "leftLowerArm": "leftHand",
        "leftHand": "leftMiddleProximal",
        "rightShoulder": "rightUpperArm",
        "rightUpperArm": "rightLowerArm",
        "rightLowerArm": "rightHand",
        "rightHand": "rightMiddleProximal",
        "leftUpperLeg": "leftLowerLeg",
        "leftLowerLeg": "leftFoot",
        "leftFoot": "leftToes",
        "rightUpperLeg": "rightLowerLeg",
        "rightLowerLeg": "rightFoot",
        "rightFoot": "rightToes",
        "leftIndexProximal": "leftIndexIntermediate",
        "leftIndexIntermediate": "leftIndexDistal",
        "leftMiddleProximal": "leftMiddleIntermediate",
        "leftMiddleIntermediate": "leftMiddleDistal",
        "leftRingProximal": "leftRingIntermediate",
        "leftRingIntermediate": "leftRingDistal",
        "leftLittleProximal": "leftLittleIntermediate",
        "leftLittleIntermediate": "leftLittleDistal",
        "leftThumbMetacarpal": "leftThumbProximal",
        "leftThumbProximal": "leftThumbDistal",
        "rightIndexProximal": "rightIndexIntermediate",
        "rightIndexIntermediate": "rightIndexDistal",
        "rightMiddleProximal": "rightMiddleIntermediate",
        "rightMiddleIntermediate": "rightMiddleDistal",
        "rightRingProximal": "rightRingIntermediate",
        "rightRingIntermediate": "rightRingDistal",
        "rightLittleProximal": "rightLittleIntermediate",
        "rightLittleIntermediate": "rightLittleDistal",
        "rightThumbMetacarpal": "rightThumbProximal",
        "rightThumbProximal": "rightThumbDistal",
    }
    ch = child_hint.get(bone)
    if ch and ch in pose.world_pos:
        return _v_norm(_v_sub(pose.world_pos[ch], pose.world_pos[bone]))
    p = parents.get(bone)
    if p and p in pose.world_pos:
        return _v_norm(_v_sub(pose.world_pos[bone], pose.world_pos[p]))
    return (0.0, 0.0, 0.0)


def _swing_quat(
    pose: HumanoidPose,
    parents: Dict[str, Optional[str]],
    bone: str,
    target_dir_world: Vec3,
    amount: float,
    max_deg: float,
) -> Quat:
    bone_dir = _bone_dir_world(pose, parents, bone)
    axis_world = _v_cross(bone_dir, _v_norm(target_dir_world))
    if _v_len(axis_world) <= 1e-8:
        return (0.0, 0.0, 0.0, 1.0)
    angle = _clamp(amount, -1.0, 1.0) * _deg(max_deg)
    axis_local = _q_rotate(_q_inv(pose.world_rot[bone]), axis_world)
    return _q_axis_angle(axis_local, angle)


def _twist_quat(pose: HumanoidPose, parents: Dict[str, Optional[str]], bone: str, amount: float, max_deg: float) -> Quat:
    bone_dir = _bone_dir_world(pose, parents, bone)
    if _v_len(bone_dir) <= 1e-8:
        return (0.0, 0.0, 0.0, 1.0)
    angle = _clamp(amount, -1.0, 1.0) * _deg(max_deg)
    axis_local = _q_rotate(_q_inv(pose.world_rot[bone]), bone_dir)
    return _q_axis_angle(axis_local, angle)


def _bend_from_stretch(stretch_value: float, max_bend_deg: float) -> float:
    v = _clamp(stretch_value, -1.0, 1.0)
    t = (1.0 - v) * 0.5  # [0..1]
    return t * _deg(max_bend_deg)


def _flatten_f32(values: Sequence[float]) -> bytes:
    return struct.pack("<" + "f" * len(values), *[float(v) for v in values])


def _build_accessor_f32(
    blob: bytearray,
    buffer_views: List[Dict[str, Any]],
    accessors: List[Dict[str, Any]],
    type_name: str,
    values_f32: bytes,
    count: int,
    min_vals: Optional[List[float]] = None,
    max_vals: Optional[List[float]] = None,
) -> int:
    while len(blob) % 4 != 0:
        blob.append(0)
    offset = len(blob)
    blob.extend(values_f32)
    buffer_view_index = len(buffer_views)
    buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(values_f32)})
    acc: Dict[str, Any] = {"bufferView": buffer_view_index, "componentType": 5126, "count": count, "type": type_name}
    if min_vals is not None:
        acc["min"] = min_vals
    if max_vals is not None:
        acc["max"] = max_vals
    accessors.append(acc)
    return len(accessors) - 1


def convert_unity_anim_to_vrma(
    *,
    template_vrm: Path,
    input_anim: Path,
    output_vrma: Path,
    fps: int = 30,
    include_fingers: bool = True,
    include_root_motion: bool = True,
) -> None:
    pose, present_bones = _load_template_humanoid_pose(template_vrm)
    nodes, bone_to_node, parents = _build_vrma_skeleton(pose, present_bones)

    curves = _parse_unity_anim_float_curves(input_anim)
    duration = _curve_duration(curves)
    if duration <= 1e-6:
        # Some clips (e.g. face layer idles) are effectively static poses with only t=0 keys.
        frame_count = 1
        times = [0.0]
    else:
        frame_count = int(math.ceil(duration * fps)) + 1
        times = [i / float(fps) for i in range(frame_count)]

    def sample(attr: str, default: float) -> List[float]:
        return _sample_curve(curves.get(attr), times, default)

    has_root_t = include_root_motion and all(
        k in curves for k in ("RootT.x", "RootT.y", "RootT.z")
    )
    has_root_q = include_root_motion and all(
        k in curves for k in ("RootQ.x", "RootQ.y", "RootQ.z", "RootQ.w")
    )

    root_t: Optional[Tuple[List[float], List[float], List[float]]] = None
    root_q: Optional[Tuple[List[float], List[float], List[float], List[float]]] = None
    if has_root_t:
        root_t = (
            sample("RootT.x", float(curves["RootT.x"][0][1])),
            sample("RootT.y", float(curves["RootT.y"][0][1])),
            sample("RootT.z", float(curves["RootT.z"][0][1])),
        )
    if has_root_q:
        root_q = (
            sample("RootQ.x", float(curves["RootQ.x"][0][1])),
            sample("RootQ.y", float(curves["RootQ.y"][0][1])),
            sample("RootQ.z", float(curves["RootQ.z"][0][1])),
            sample("RootQ.w", float(curves["RootQ.w"][0][1])),
        )

    # Safe subset of Humanoid muscles (best-effort). Unused/missing tracks stay at rest pose.
    muscle_attrs = [
        "Spine Front-Back",
        "Spine Left-Right",
        "Spine Twist Left-Right",
        "Chest Front-Back",
        "Chest Left-Right",
        "Chest Twist Left-Right",
        "Neck Nod Down-Up",
        "Neck Tilt Left-Right",
        "Neck Turn Left-Right",
        "Head Nod Down-Up",
        "Head Tilt Left-Right",
        "Head Turn Left-Right",
        "Left Shoulder Down-Up",
        "Left Shoulder Front-Back",
        "Right Shoulder Down-Up",
        "Right Shoulder Front-Back",
        "Left Arm Down-Up",
        "Left Arm Front-Back",
        "Left Arm Twist In-Out",
        "Right Arm Down-Up",
        "Right Arm Front-Back",
        "Right Arm Twist In-Out",
        "Left Forearm Stretch",
        "Left Forearm Twist In-Out",
        "Right Forearm Stretch",
        "Right Forearm Twist In-Out",
        "Left Hand Down-Up",
        "Left Hand In-Out",
        "Right Hand Down-Up",
        "Right Hand In-Out",
        "Left Upper Leg Front-Back",
        "Left Upper Leg In-Out",
        "Left Upper Leg Twist In-Out",
        "Right Upper Leg Front-Back",
        "Right Upper Leg In-Out",
        "Right Upper Leg Twist In-Out",
        "Left Lower Leg Stretch",
        "Left Lower Leg Twist In-Out",
        "Right Lower Leg Stretch",
        "Right Lower Leg Twist In-Out",
        "Left Foot Up-Down",
        "Left Foot Twist In-Out",
        "Right Foot Up-Down",
        "Right Foot Twist In-Out",
        "Left Toes Up-Down",
        "Right Toes Up-Down",
    ]

    samples: Dict[str, List[float]] = {}
    for attr in muscle_attrs:
        default = 1.0 if "Stretch" in attr else 0.0
        samples[attr] = sample(attr, default)

    finger_map: List[Tuple[str, str, float]] = []
    if include_fingers:
        for side in ("Left", "Right"):
            prefix = "left" if side == "Left" else "right"
            finger_map.extend(
                [
                    (f"{side}Hand.Index.1 Stretched", f"{prefix}IndexProximal", 70.0),
                    (f"{side}Hand.Index.2 Stretched", f"{prefix}IndexIntermediate", 55.0),
                    (f"{side}Hand.Index.3 Stretched", f"{prefix}IndexDistal", 45.0),
                    (f"{side}Hand.Middle.1 Stretched", f"{prefix}MiddleProximal", 70.0),
                    (f"{side}Hand.Middle.2 Stretched", f"{prefix}MiddleIntermediate", 55.0),
                    (f"{side}Hand.Middle.3 Stretched", f"{prefix}MiddleDistal", 45.0),
                    (f"{side}Hand.Ring.1 Stretched", f"{prefix}RingProximal", 70.0),
                    (f"{side}Hand.Ring.2 Stretched", f"{prefix}RingIntermediate", 55.0),
                    (f"{side}Hand.Ring.3 Stretched", f"{prefix}RingDistal", 45.0),
                    (f"{side}Hand.Little.1 Stretched", f"{prefix}LittleProximal", 70.0),
                    (f"{side}Hand.Little.2 Stretched", f"{prefix}LittleIntermediate", 55.0),
                    (f"{side}Hand.Little.3 Stretched", f"{prefix}LittleDistal", 45.0),
                    (f"{side}Hand.Thumb.1 Stretched", f"{prefix}ThumbMetacarpal", 45.0),
                    (f"{side}Hand.Thumb.2 Stretched", f"{prefix}ThumbProximal", 45.0),
                    (f"{side}Hand.Thumb.3 Stretched", f"{prefix}ThumbDistal", 45.0),
                ]
            )
        for attr, _, _ in finger_map:
            samples.setdefault(attr, sample(attr, 1.0))

    hips_pos = pose.world_pos.get("hips", (0.0, 0.0, 0.0))
    left_out = _v_norm(_v_sub(pose.world_pos.get("leftUpperLeg", hips_pos), hips_pos))
    right_out = _v_norm(_v_sub(pose.world_pos.get("rightUpperLeg", hips_pos), hips_pos))

    def has_bone(name: str) -> bool:
        return name in bone_to_node and name in pose.world_rot and name in pose.world_pos

    bones_to_animate: List[str] = [
        "hips",
        "spine",
        "chest",
        "neck",
        "head",
        "leftShoulder",
        "rightShoulder",
        "leftUpperArm",
        "leftLowerArm",
        "leftHand",
        "rightUpperArm",
        "rightLowerArm",
        "rightHand",
        "leftUpperLeg",
        "leftLowerLeg",
        "leftFoot",
        "leftToes",
        "rightUpperLeg",
        "rightLowerLeg",
        "rightFoot",
        "rightToes",
    ]
    if include_fingers:
        bones_to_animate.extend([b for _, b, _ in finger_map])
    bones_to_animate = [b for b in bones_to_animate if has_bone(b)]
    if root_q is None and "hips" in bones_to_animate:
        bones_to_animate.remove("hips")

    rest_local_rot: Dict[str, Quat] = {}
    for bone, node_idx in bone_to_node.items():
        r = nodes[node_idx].get("rotation") or [0.0, 0.0, 0.0, 1.0]
        rest_local_rot[bone] = _q_norm((float(r[0]), float(r[1]), float(r[2]), float(r[3])))

    rotations: Dict[str, List[Quat]] = {b: [] for b in bones_to_animate}
    hips_translations: Optional[List[Vec3]] = None
    if root_t is not None and "hips" in bone_to_node:
        node_idx = bone_to_node["hips"]
        t0 = nodes[node_idx].get("translation") or [0.0, 0.0, 0.0]
        base = (float(t0[0]), float(t0[1]), float(t0[2]))
        rx, ry, rz = root_t
        x0, y0, z0 = float(rx[0]), float(ry[0]), float(rz[0])
        hips_translations = []
        for fi in range(frame_count):
            dx = float(rx[fi]) - x0
            dy = float(ry[fi]) - y0
            dz = float(rz[fi]) - z0
            gx, gy, gz = _unity_vec_to_gltf((dx, dy, dz))
            hips_translations.append((base[0] + gx, base[1] + gy, base[2] + gz))

    hips_root_q0: Optional[Quat] = None
    prev_root_q: Optional[Quat] = None
    if root_q is not None and "hips" in rotations:
        qx, qy, qz, qw = root_q
        hips_root_q0 = _unity_quat_to_gltf((float(qx[0]), float(qy[0]), float(qz[0]), float(qw[0])))
        prev_root_q = hips_root_q0

    for fi in range(frame_count):
        if root_q is not None and "hips" in rotations and hips_root_q0 is not None and prev_root_q is not None:
            qx, qy, qz, qw = root_q
            qi = _unity_quat_to_gltf((float(qx[fi]), float(qy[fi]), float(qz[fi]), float(qw[fi])))
            if _q_dot(prev_root_q, qi) < 0:
                qi = (-qi[0], -qi[1], -qi[2], -qi[3])
            prev_root_q = qi
            delta = _q_mul(_q_inv(hips_root_q0), qi)
            rotations["hips"].append(_q_mul(rest_local_rot["hips"], delta))

        if has_bone("spine"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "spine", WORLD_FWD, samples["Spine Front-Back"][fi], 20.0))
            q = _q_mul(q, _swing_quat(pose, parents, "spine", WORLD_RIGHT, samples["Spine Left-Right"][fi], 15.0))
            q = _q_mul(q, _twist_quat(pose, parents, "spine", samples["Spine Twist Left-Right"][fi], 25.0))
            rotations["spine"].append(_q_mul(rest_local_rot["spine"], q))

        if has_bone("chest"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "chest", WORLD_FWD, samples["Chest Front-Back"][fi], 20.0))
            q = _q_mul(q, _swing_quat(pose, parents, "chest", WORLD_RIGHT, samples["Chest Left-Right"][fi], 15.0))
            q = _q_mul(q, _twist_quat(pose, parents, "chest", samples["Chest Twist Left-Right"][fi], 25.0))
            rotations["chest"].append(_q_mul(rest_local_rot["chest"], q))

        if has_bone("neck"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "neck", WORLD_FWD, samples["Neck Nod Down-Up"][fi], 25.0))
            q = _q_mul(q, _swing_quat(pose, parents, "neck", WORLD_RIGHT, samples["Neck Tilt Left-Right"][fi], 20.0))
            q = _q_mul(q, _twist_quat(pose, parents, "neck", samples["Neck Turn Left-Right"][fi], 35.0))
            rotations["neck"].append(_q_mul(rest_local_rot["neck"], q))

        if has_bone("head"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "head", WORLD_FWD, samples["Head Nod Down-Up"][fi], 25.0))
            q = _q_mul(q, _swing_quat(pose, parents, "head", WORLD_RIGHT, samples["Head Tilt Left-Right"][fi], 20.0))
            q = _q_mul(q, _twist_quat(pose, parents, "head", samples["Head Turn Left-Right"][fi], 45.0))
            rotations["head"].append(_q_mul(rest_local_rot["head"], q))

        if has_bone("leftShoulder"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "leftShoulder", WORLD_UP, samples["Left Shoulder Down-Up"][fi], 20.0))
            q = _q_mul(q, _swing_quat(pose, parents, "leftShoulder", WORLD_FWD, samples["Left Shoulder Front-Back"][fi], 20.0))
            rotations["leftShoulder"].append(_q_mul(rest_local_rot["leftShoulder"], q))

        if has_bone("rightShoulder"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "rightShoulder", WORLD_UP, samples["Right Shoulder Down-Up"][fi], 20.0))
            q = _q_mul(q, _swing_quat(pose, parents, "rightShoulder", WORLD_FWD, samples["Right Shoulder Front-Back"][fi], 20.0))
            rotations["rightShoulder"].append(_q_mul(rest_local_rot["rightShoulder"], q))

        if has_bone("leftUpperArm"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "leftUpperArm", WORLD_UP, samples["Left Arm Down-Up"][fi], 70.0))
            q = _q_mul(q, _swing_quat(pose, parents, "leftUpperArm", WORLD_FWD, samples["Left Arm Front-Back"][fi], 70.0))
            q = _q_mul(q, _twist_quat(pose, parents, "leftUpperArm", samples["Left Arm Twist In-Out"][fi], 60.0))
            rotations["leftUpperArm"].append(_q_mul(rest_local_rot["leftUpperArm"], q))

        if has_bone("rightUpperArm"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "rightUpperArm", WORLD_UP, samples["Right Arm Down-Up"][fi], 70.0))
            q = _q_mul(q, _swing_quat(pose, parents, "rightUpperArm", WORLD_FWD, samples["Right Arm Front-Back"][fi], 70.0))
            q = _q_mul(q, _twist_quat(pose, parents, "rightUpperArm", samples["Right Arm Twist In-Out"][fi], 60.0))
            rotations["rightUpperArm"].append(_q_mul(rest_local_rot["rightUpperArm"], q))

        if has_bone("leftLowerArm"):
            bend = _bend_from_stretch(samples["Left Forearm Stretch"][fi], 120.0)
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "leftLowerArm", WORLD_UP, 1.0, math.degrees(bend)))
            q = _q_mul(q, _twist_quat(pose, parents, "leftLowerArm", samples["Left Forearm Twist In-Out"][fi], 90.0))
            rotations["leftLowerArm"].append(_q_mul(rest_local_rot["leftLowerArm"], q))

        if has_bone("rightLowerArm"):
            bend = _bend_from_stretch(samples["Right Forearm Stretch"][fi], 120.0)
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "rightLowerArm", WORLD_UP, 1.0, math.degrees(bend)))
            q = _q_mul(q, _twist_quat(pose, parents, "rightLowerArm", samples["Right Forearm Twist In-Out"][fi], 90.0))
            rotations["rightLowerArm"].append(_q_mul(rest_local_rot["rightLowerArm"], q))

        if has_bone("leftHand"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "leftHand", WORLD_UP, samples["Left Hand Down-Up"][fi], 35.0))
            q = _q_mul(q, _swing_quat(pose, parents, "leftHand", WORLD_FWD, samples["Left Hand In-Out"][fi], 35.0))
            rotations["leftHand"].append(_q_mul(rest_local_rot["leftHand"], q))

        if has_bone("rightHand"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "rightHand", WORLD_UP, samples["Right Hand Down-Up"][fi], 35.0))
            q = _q_mul(q, _swing_quat(pose, parents, "rightHand", WORLD_FWD, samples["Right Hand In-Out"][fi], 35.0))
            rotations["rightHand"].append(_q_mul(rest_local_rot["rightHand"], q))

        if has_bone("leftUpperLeg"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "leftUpperLeg", WORLD_FWD, samples["Left Upper Leg Front-Back"][fi], 65.0))
            q = _q_mul(q, _swing_quat(pose, parents, "leftUpperLeg", left_out, samples["Left Upper Leg In-Out"][fi], 45.0))
            q = _q_mul(q, _twist_quat(pose, parents, "leftUpperLeg", samples["Left Upper Leg Twist In-Out"][fi], 55.0))
            rotations["leftUpperLeg"].append(_q_mul(rest_local_rot["leftUpperLeg"], q))

        if has_bone("rightUpperLeg"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "rightUpperLeg", WORLD_FWD, samples["Right Upper Leg Front-Back"][fi], 65.0))
            q = _q_mul(q, _swing_quat(pose, parents, "rightUpperLeg", right_out, samples["Right Upper Leg In-Out"][fi], 45.0))
            q = _q_mul(q, _twist_quat(pose, parents, "rightUpperLeg", samples["Right Upper Leg Twist In-Out"][fi], 55.0))
            rotations["rightUpperLeg"].append(_q_mul(rest_local_rot["rightUpperLeg"], q))

        if has_bone("leftLowerLeg"):
            bend = _bend_from_stretch(samples["Left Lower Leg Stretch"][fi], 130.0)
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "leftLowerLeg", WORLD_BACK, 1.0, math.degrees(bend)))
            q = _q_mul(q, _twist_quat(pose, parents, "leftLowerLeg", samples["Left Lower Leg Twist In-Out"][fi], 30.0))
            rotations["leftLowerLeg"].append(_q_mul(rest_local_rot["leftLowerLeg"], q))

        if has_bone("rightLowerLeg"):
            bend = _bend_from_stretch(samples["Right Lower Leg Stretch"][fi], 130.0)
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "rightLowerLeg", WORLD_BACK, 1.0, math.degrees(bend)))
            q = _q_mul(q, _twist_quat(pose, parents, "rightLowerLeg", samples["Right Lower Leg Twist In-Out"][fi], 30.0))
            rotations["rightLowerLeg"].append(_q_mul(rest_local_rot["rightLowerLeg"], q))

        if has_bone("leftFoot"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "leftFoot", WORLD_UP, samples["Left Foot Up-Down"][fi], 45.0))
            q = _q_mul(q, _twist_quat(pose, parents, "leftFoot", samples["Left Foot Twist In-Out"][fi], 35.0))
            rotations["leftFoot"].append(_q_mul(rest_local_rot["leftFoot"], q))

        if has_bone("rightFoot"):
            q = (0.0, 0.0, 0.0, 1.0)
            q = _q_mul(q, _swing_quat(pose, parents, "rightFoot", WORLD_UP, samples["Right Foot Up-Down"][fi], 45.0))
            q = _q_mul(q, _twist_quat(pose, parents, "rightFoot", samples["Right Foot Twist In-Out"][fi], 35.0))
            rotations["rightFoot"].append(_q_mul(rest_local_rot["rightFoot"], q))

        if has_bone("leftToes"):
            q = _q_mul(rest_local_rot["leftToes"], _swing_quat(pose, parents, "leftToes", WORLD_UP, samples["Left Toes Up-Down"][fi], 25.0))
            rotations["leftToes"].append(q)

        if has_bone("rightToes"):
            q = _q_mul(rest_local_rot["rightToes"], _swing_quat(pose, parents, "rightToes", WORLD_UP, samples["Right Toes Up-Down"][fi], 25.0))
            rotations["rightToes"].append(q)

        if include_fingers:
            for attr, bone, max_bend in finger_map:
                if not has_bone(bone):
                    continue
                bend = _bend_from_stretch(samples[attr][fi], max_bend)
                q = _q_mul(rest_local_rot[bone], _swing_quat(pose, parents, bone, WORLD_DOWN, 1.0, math.degrees(bend)))
                rotations[bone].append(q)

    buffer_views: List[Dict[str, Any]] = []
    accessors: List[Dict[str, Any]] = []
    blob = bytearray()

    time_accessor = _build_accessor_f32(
        blob,
        buffer_views,
        accessors,
        "SCALAR",
        _flatten_f32(times),
        count=len(times),
        min_vals=[min(times)],
        max_vals=[max(times)],
    )

    animation: Dict[str, Any] = {"samplers": [], "channels": []}

    def add_rotation_track(node_index: int, quats: Sequence[Quat]) -> None:
        flat: List[float] = []
        for x, y, z, w in quats:
            flat.extend([float(x), float(y), float(z), float(w)])
        out_accessor = _build_accessor_f32(
            blob,
            buffer_views,
            accessors,
            "VEC4",
            _flatten_f32(flat),
            count=len(quats),
        )
        sampler_index = len(animation["samplers"])
        animation["samplers"].append({"input": time_accessor, "output": out_accessor, "interpolation": "LINEAR"})
        animation["channels"].append({"sampler": sampler_index, "target": {"node": node_index, "path": "rotation"}})

    def add_translation_track(node_index: int, positions: Sequence[Vec3]) -> None:
        flat: List[float] = []
        for x, y, z in positions:
            flat.extend([float(x), float(y), float(z)])
        out_accessor = _build_accessor_f32(
            blob,
            buffer_views,
            accessors,
            "VEC3",
            _flatten_f32(flat),
            count=len(positions),
        )
        sampler_index = len(animation["samplers"])
        animation["samplers"].append({"input": time_accessor, "output": out_accessor, "interpolation": "LINEAR"})
        animation["channels"].append(
            {"sampler": sampler_index, "target": {"node": node_index, "path": "translation"}}
        )

    if hips_translations is not None and "hips" in bone_to_node:
        add_translation_track(bone_to_node["hips"], hips_translations)

    for bone in bones_to_animate:
        add_rotation_track(bone_to_node[bone], rotations[bone])

    while len(blob) % 4 != 0:
        blob.append(0)

    roots = [bone_to_node["hips"]] if "hips" in bone_to_node else [0]
    vrma: Dict[str, Any] = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": roots}],
        "nodes": nodes,
        "animations": [animation],
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(blob)}],
        "accessors": accessors,
        "extensionsUsed": ["VRMC_vrm_animation"],
        "extensions": {
            "VRMC_vrm_animation": {
                "specVersion": "1.0",
                "humanoid": {"humanBones": {b: {"node": bone_to_node[b]} for b in present_bones if b in bone_to_node}},
            }
        },
    }

    _write_glb(output_vrma, vrma, bytes(blob))


def _parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Convert Unity Humanoid .anim (YAML text) to VRM Animation .vrma without Unity (best-effort)."
    )
    p.add_argument("--template-vrm", type=Path, required=True, help="VRM 1.0 model used as the humanoid skeleton template.")
    p.add_argument("--input", type=Path, help="Input .anim file")
    p.add_argument("--input-dir", type=Path, help="Directory containing .anim files (batch)")
    p.add_argument("--output", type=Path, help="Output .vrma file (single)")
    p.add_argument("--output-dir", type=Path, help="Output directory (batch)")
    p.add_argument("--fps", type=int, default=30, help="Sampling FPS (default: 30)")
    p.add_argument("--no-fingers", action="store_true", help="Do not convert finger curl tracks")
    p.add_argument("--no-root-motion", action="store_true", help="Do not export RootT/RootQ onto hips")
    return p.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = _parse_args(argv)
    template = args.template_vrm
    if not template.exists():
        raise SystemExit(f"--template-vrm not found: {template}")

    if args.input and args.output:
        convert_unity_anim_to_vrma(
            template_vrm=template,
            input_anim=args.input,
            output_vrma=args.output,
            fps=int(args.fps),
            include_fingers=not args.no_fingers,
            include_root_motion=not args.no_root_motion,
        )
        print(f"OK: {args.output}")
        return 0

    if args.input_dir and args.output_dir:
        in_dir: Path = args.input_dir
        out_dir: Path = args.output_dir
        out_dir.mkdir(parents=True, exist_ok=True)
        files = sorted(in_dir.rglob("*.anim"))
        if not files:
            raise SystemExit(f"No .anim found under: {in_dir}")
        for f in files:
            rel = f.relative_to(in_dir)
            out = out_dir / rel.with_suffix(".vrma")
            out.parent.mkdir(parents=True, exist_ok=True)
            convert_unity_anim_to_vrma(
                template_vrm=template,
                input_anim=f,
                output_vrma=out,
                fps=int(args.fps),
                include_fingers=not args.no_fingers,
                include_root_motion=not args.no_root_motion,
            )
            print(f"OK: {out}")
        return 0

    raise SystemExit("Provide either --input + --output, or --input-dir + --output-dir")


if __name__ == "__main__":
    raise SystemExit(main())
