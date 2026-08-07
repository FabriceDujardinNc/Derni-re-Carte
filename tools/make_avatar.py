# Avatar "cartoon soigné" de Dernière Carte (style Party Animals/Fall Guys),
# sculpté en METABALLS : les volumes fusionnent organiquement (fini les
# sphères qui se chevauchent). Grosse tête expressive, corps potelé, nez,
# oreilles, tignasse, mains à pouces. Chaque partie garde son NOM (le jeu
# s'y accroche) et son ORIGINE est à l'ARTICULATION (pivot naturel).
# Usage : blender --background --python tools/make_avatar.py
import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)

def make_material(name, color, roughness=0.8):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return material

SKIN = make_material("Skin", (0.72, 0.55, 0.80, 1.0))
HAIR = make_material("Hair", (0.18, 0.12, 0.09, 1.0), 0.9)
EYE = make_material("Eye", (0.97, 0.97, 0.95, 1.0), 0.25)
PUPIL = make_material("Pupil", (0.06, 0.05, 0.08, 1.0), 0.2)

def metaball_part(name, origin, balls, material, resolution=0.03):
    """Une partie du corps : des boules qui FUSIONNENT, converties en maillage."""
    data = bpy.data.metaballs.new(name)
    data.resolution = resolution
    obj = bpy.data.objects.new(name, data)
    obj.location = origin
    bpy.context.collection.objects.link(obj)
    for co, radius in balls:
        element = data.elements.new()
        element.co = co
        element.radius = radius
    bpy.context.view_layer.objects.active = obj
    for other in bpy.context.selected_objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    converted = bpy.context.object
    converted.name = name
    converted.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return converted

def sphere_part(name, location, scale, material):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, location=location,
                                         segments=24, ring_count=16)
    part = bpy.context.object
    part.name = name
    part.scale = scale
    part.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return part

# ---- TORSE potelé (origine : hanches, z 0.62) : poire assumée. ----
metaball_part("Body", (0, 0, 0.62), [
    ((0, 0, -0.02), 0.135), ((-0.05, 0, -0.03), 0.11), ((0.05, 0, -0.03), 0.11),
    ((0, 0.03, 0.10), 0.14), ((0, 0, 0.22), 0.12),
    ((0, 0.01, 0.32), 0.105),
    ((-0.13, 0, 0.37), 0.07), ((0.13, 0, 0.37), 0.07),
    ((0, -0.05, 0.28), 0.09),
], SKIN)

# ---- COU court (origine : z 0.98). ----
metaball_part("Neck", (0, 0, 0.98), [((0, 0, 0.01), 0.065)], SKIN)

# ---- GROSSE TÊTE expressive (origine : z 1.06 = PIVOT du regard). ----
metaball_part("Head", (0, 0, 1.06), [
    ((0, -0.01, 0.19), 0.195), ((0, -0.10, 0.17), 0.13),
    ((0, 0.09, 0.22), 0.135), ((0, 0.085, 0.06), 0.10),
    ((0, 0.13, 0.02), 0.055),
    ((-0.10, 0.08, 0.10), 0.08), ((0.10, 0.08, 0.10), 0.08),
], SKIN)

# ---- Nez patate, grandes oreilles, tignasse. ----
metaball_part("Nose", (0, 0, 1.06), [
    ((0, 0.20, 0.14), 0.038), ((0, 0.215, 0.115), 0.032),
], SKIN, resolution=0.018)
metaball_part("EarL", (0, 0, 1.06), [((-0.19, -0.02, 0.16), 0.05)], SKIN, resolution=0.02)
metaball_part("EarR", (0, 0, 1.06), [((0.19, -0.02, 0.16), 0.05)], SKIN, resolution=0.02)
metaball_part("Hair", (0, 0, 1.06), [
    ((0, -0.04, 0.325), 0.15), ((0, 0.09, 0.30), 0.115),
    ((-0.11, -0.02, 0.29), 0.10), ((0.11, -0.02, 0.29), 0.10),
    ((0, -0.14, 0.235), 0.10), ((0.06, 0.16, 0.27), 0.05),
], HAIR)

# ---- GRANDS yeux cartoon (la fenêtre du bluff). ----
for side in (-1, 1):
    tag = "L" if side < 0 else "R"
    sphere_part(f"EyeWhite{tag}", (0.082 * side, 0.155, 1.29), (0.052, 0.038, 0.06), EYE)
    sphere_part(f"Pupil{tag}", (0.082 * side, 0.188, 1.29), (0.024, 0.014, 0.028), PUPIL)

# ---- BRAS courts et ronds (origine : ÉPAULE), MAINS à pouce. ----
for side in (-1, 1):
    tag = "L" if side < 0 else "R"
    metaball_part(f"Arm{tag}", (0.175 * side, 0, 0.96), [
        ((0.005 * side, 0, -0.02), 0.065), ((0.02 * side, 0.005, -0.11), 0.055),
        ((0.035 * side, 0, -0.20), 0.048),
    ], SKIN)
    metaball_part(f"Hand{tag}", (0.215 * side, 0.005, 0.70), [
        ((0, 0.015, -0.04), 0.055), ((0, 0.03, -0.085), 0.04),
        ((-0.025 * side, 0.032, -0.11), 0.024), ((0.002, 0.035, -0.118), 0.024),
        ((0.026 * side, 0.032, -0.11), 0.024),
        ((-0.055 * side, 0.04, -0.035), 0.028),
    ], SKIN, resolution=0.018)

# ---- JAMBES courtes, GROS pieds ronds. ----
for side in (-1, 1):
    tag = "L" if side < 0 else "R"
    metaball_part(f"Leg{tag}", (0.10 * side, 0, 0.52), [
        ((0, 0.005, -0.08), 0.075), ((0, 0, -0.20), 0.062),
        ((0, -0.005, -0.32), 0.05),
    ], SKIN)
    metaball_part(f"Foot{tag}", (0.10 * side, 0, 0.09), [
        ((0, -0.03, -0.01), 0.055), ((0, 0.06, -0.02), 0.055),
        ((0, 0.13, -0.025), 0.045),
    ], SKIN, resolution=0.02)

bpy.ops.export_scene.gltf(
    filepath="C:/Users/Gladius/dev/Derniere-Carte/assets/models/avatar_test.glb",
    export_format="GLB")
print("AVATAR_CARTOON_EXPORTE")
