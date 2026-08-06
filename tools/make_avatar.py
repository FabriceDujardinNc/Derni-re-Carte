# Génère l'avatar de test "pâte à modeler" de Dernière Carte et l'exporte en .glb.
# Usage : blender --background --python tools/make_avatar.py
import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)

def make_material(name, color):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = color
    material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    return material

# "Skin" sera recoloré par le jeu (couleur du joueur + dégradation).
SKIN = make_material("Skin", (0.75, 0.55, 0.85, 1.0))
EYE = make_material("Eye", (0.96, 0.96, 0.94, 1.0))
PUPIL = make_material("Pupil", (0.06, 0.06, 0.09, 1.0))

def add_part(name, location, scale, material, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, location=location,
                                         segments=24, ring_count=16)
    part = bpy.context.object
    part.name = name
    part.scale = scale
    part.rotation_euler = rotation
    part.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return part

# Proportions cartoon (~1,7 m de haut, grosse tête expressive). Z-up Blender,
# face vers -Y (devient -Z dans Godot à l'export glTF).
add_part("Body", (0, 0, 0.62), (0.34, 0.30, 0.44), SKIN)
add_part("Head", (0, 0, 1.32), (0.31, 0.30, 0.29), SKIN)
for side in (-1, 1):
    add_part(f"EyeWhite{'L' if side < 0 else 'R'}", (0.115 * side, -0.235, 1.36),
             (0.06, 0.045, 0.07), EYE)
    add_part(f"Pupil{'L' if side < 0 else 'R'}", (0.115 * side, -0.272, 1.36),
             (0.028, 0.02, 0.034), PUPIL)
    add_part(f"Arm{'L' if side < 0 else 'R'}", (0.40 * side, 0, 0.76),
             (0.10, 0.10, 0.30), SKIN, (0.0, 0.28 * side, 0.0))
    add_part(f"Hand{'L' if side < 0 else 'R'}", (0.47 * side, 0, 0.47),
             (0.095, 0.095, 0.10), SKIN)
    add_part(f"Leg{'L' if side < 0 else 'R'}", (0.15 * side, 0, 0.22),
             (0.115, 0.115, 0.24), SKIN)
    add_part(f"Foot{'L' if side < 0 else 'R'}", (0.15 * side, -0.06, 0.05),
             (0.11, 0.16, 0.07), SKIN)

bpy.ops.export_scene.gltf(
    filepath="C:/Users/Gladius/dev/Derniere-Carte/assets/models/avatar_test.glb",
    export_format="GLB")
print("AVATAR_EXPORTE")
