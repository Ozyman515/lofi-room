extends SceneTree
## Turns the T-Rex kaiju mesh data (made by pack/trex/gamemesh.py) into mesh resources the room loads:
##   godot --headless --path . -s pack/trex/bake.gd
## Writes res://kaiju/full/*.res (the giant outside) and res://kaiju/toy/*.res (the lighter nightstand toy).

func _init() -> void:
	for lod in ["full", "toy"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://kaiju/" + lod))
		var f := FileAccess.open("res://pack/trex/kaiju_%s.bin" % lod, FileAccess.READ)
		var n := f.get_32()
		for p in n:
			var name := f.get_buffer(f.get_8()).get_string_from_utf8()
			var nv := f.get_32()
			var ni := f.get_32()
			var hasc := f.get_8()
			var vf := f.get_buffer(nv * 12).to_float32_array()
			var nf := f.get_buffer(nv * 12).to_float32_array()
			var cf := PackedFloat32Array()
			if hasc:
				cf = f.get_buffer(nv * 12).to_float32_array()
			var idx := f.get_buffer(ni * 4).to_int32_array()
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			verts.resize(nv)
			norms.resize(nv)
			for i in nv:
				verts[i] = Vector3(vf[i * 3], vf[i * 3 + 1], vf[i * 3 + 2])
				norms[i] = Vector3(nf[i * 3], nf[i * 3 + 1], nf[i * 3 + 2])
			if hasc:
				cols.resize(nv)
				for i in nv:
					cols[i] = Color(cf[i * 3], cf[i * 3 + 1], cf[i * 3 + 2])
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			if hasc:
				arr[Mesh.ARRAY_COLOR] = cols
			arr[Mesh.ARRAY_INDEX] = idx
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var path := "res://kaiju/%s/%s.res" % [lod, name]
			var err := ResourceSaver.save(m, path, ResourceSaver.FLAG_COMPRESS)
			print("baked ", path, " ", nv, " verts ", ni / 3, " tris  err=", err)
		var np := f.get_32()
		for p in np:
			var name := f.get_buffer(f.get_8()).get_string_from_utf8()
			var v := f.get_buffer(12).to_float32_array()
			print("pivot ", lod, " ", name, " ", Vector3(v[0], v[1], v[2]))
	quit()
