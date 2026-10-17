extends Node
## Plays an animated GIF (or shows a still image) on a ShaderMaterial.
## Godot can't load GIFs itself, so this decodes them on a background thread and
## cycles the frames. Looks for <base>.gif, then .png/.jpg/.jpeg/.webp.

const MAX_FRAMES := 400

var frames: Array[ImageTexture] = []
var delays: Array[float] = []

var _mat: ShaderMaterial
var _thread: Thread
var _mutex := Mutex.new()
var _pending: Array = []
var _finished := false
var _loaded := false
var _cancel := false
var _t := 0.0
var _idx := 0
var _k_tex := "media_tex"
var _k_aspect := "media_aspect"
var _k_use := "use_media"


func setup(mat: ShaderMaterial, base_path: String, prefix: String = "media") -> void:
	_mat = mat
	if prefix == "console":
		_k_tex = "console_tex"
		_k_aspect = "console_aspect"
		_k_use = "console_file"
	set_process(false)
	for ext in ["gif", "png", "jpg", "jpeg", "webp"]:
		var path := "%s.%s" % [base_path, ext]
		if not FileAccess.file_exists(path):
			continue
		if ext == "gif":
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.size() > 13:
				_thread = Thread.new()
				_thread.start(_decode_gif.bind(bytes))
				set_process(true)
		else:
			var img := Image.load_from_file(path)
			if img != null:
				_add_frame(img, 1.0)
				_loaded = true
		return


func _exit_tree() -> void:
	_cancel = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _process(delta: float) -> void:
	# pick up frames the worker thread has finished (a few per frame, so loading never hitches)
	var take: Array = []
	var done := false
	_mutex.lock()
	while take.size() < 3 and not _pending.is_empty():
		take.append(_pending.pop_front())
	done = _finished and _pending.is_empty()
	_mutex.unlock()
	for item in take:
		_add_frame(item[0], item[1])
	if done and not _loaded:
		_loaded = true
		if _thread != null:
			_thread.wait_to_finish()
			_thread = null
	if not _loaded:
		return
	if frames.size() < 2:
		set_process(false)
		return
	_t += delta
	var advanced := false
	while _t >= delays[_idx]:
		_t -= delays[_idx]
		_idx = (_idx + 1) % frames.size()
		advanced = true
	if advanced:
		_mat.set_shader_parameter(_k_tex, frames[_idx])


func _add_frame(img: Image, delay_s: float) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	frames.append(tex)
	delays.append(delay_s)
	if frames.size() == 1:
		_mat.set_shader_parameter(_k_tex, tex)
		_mat.set_shader_parameter(_k_aspect, float(img.get_width()) / maxf(float(img.get_height()), 1.0))
		_mat.set_shader_parameter(_k_use, true)


func _finish() -> void:
	_mutex.lock()
	_finished = true
	_mutex.unlock()


static func _u16(b: PackedByteArray, p: int) -> int:
	return int(b[p]) | (int(b[p + 1]) << 8)


static func _interlace_row(r: int, ih: int) -> int:
	var p1 := (ih + 7) >> 3
	var p2 := (ih + 3) >> 3
	var p3 := (ih + 1) >> 2
	if r < p1:
		return r * 8
	r -= p1
	if r < p2:
		return 4 + r * 8
	r -= p2
	if r < p3:
		return 2 + r * 4
	r -= p3
	return 1 + r * 2


# ---- GIF decoding (runs on the worker thread) ----

func _decode_gif(b: PackedByteArray) -> void:
	var n := b.size()
	if b[0] != 71 or b[1] != 73 or b[2] != 70:
		_finish()
		return
	var w := _u16(b, 6)
	var h := _u16(b, 8)
	if w <= 0 or h <= 0:
		_finish()
		return
	var packed := int(b[10])
	var pos := 13
	var gct := PackedByteArray()
	if (packed & 0x80) != 0:
		var gsize := 3 * (1 << ((packed & 7) + 1))
		gct = b.slice(pos, pos + gsize)
		pos += gsize
	var canvas := PackedByteArray()
	canvas.resize(w * h * 4)
	var prev_canvas := PackedByteArray()
	var disposal := 0
	var transparent := -1
	var delay := 10
	var prev_disposal := 0
	var prev_rect := Rect2i()
	var count := 0
	while pos < n and count < MAX_FRAMES and not _cancel:
		var c := int(b[pos])
		pos += 1
		if c == 0x3B:
			break
		elif c == 0x21:
			var label := int(b[pos])
			pos += 1
			if label == 0xF9 and pos + 4 < n:
				var pk := int(b[pos + 1])
				disposal = (pk >> 2) & 7
				transparent = int(b[pos + 4]) if (pk & 1) != 0 else -1
				delay = _u16(b, pos + 2)
			while pos < n:
				var sz := int(b[pos])
				pos += 1
				if sz == 0:
					break
				pos += sz
		elif c == 0x2C:
			var ix := _u16(b, pos)
			var iy := _u16(b, pos + 2)
			var iw := _u16(b, pos + 4)
			var ih := _u16(b, pos + 6)
			var ipk := int(b[pos + 8])
			pos += 9
			var palette := gct
			if (ipk & 0x80) != 0:
				var lsz := 3 * (1 << ((ipk & 7) + 1))
				palette = b.slice(pos, pos + lsz)
				pos += lsz
			var interlaced := (ipk & 0x40) != 0
			var min_code := int(b[pos])
			pos += 1
			var data := PackedByteArray()
			while pos < n:
				var sz2 := int(b[pos])
				pos += 1
				if sz2 == 0:
					break
				data.append_array(b.slice(pos, pos + sz2))
				pos += sz2
			var idx := _lzw(data, min_code, iw * ih)

			# undo the previous frame as its disposal method asks
			if prev_disposal == 2:
				for yy in range(prev_rect.position.y, mini(prev_rect.end.y, h)):
					var o0 := (yy * w + prev_rect.position.x) * 4
					var o1 := (yy * w + mini(prev_rect.end.x, w)) * 4
					for o in range(o0, o1):
						canvas[o] = 0
			elif prev_disposal == 3 and prev_canvas.size() == canvas.size():
				canvas = prev_canvas.duplicate()
			if disposal == 3:
				prev_canvas = canvas.duplicate()

			var pal_n := int(palette.size() / 3.0)
			for r in ih:
				var dest := _interlace_row(r, ih) if interlaced else r
				var y := iy + dest
				if y >= h:
					continue
				var src := r * iw
				for cc in iw:
					var x := ix + cc
					if x >= w:
						break
					var ci := int(idx[src + cc])
					if ci == transparent or ci >= pal_n:
						continue
					var o := (y * w + x) * 4
					var pidx := ci * 3
					canvas[o] = palette[pidx]
					canvas[o + 1] = palette[pidx + 1]
					canvas[o + 2] = palette[pidx + 2]
					canvas[o + 3] = 255

			var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, canvas)
			var secs := float(delay) / 100.0
			if delay <= 1:
				secs = 0.1
			_mutex.lock()
			_pending.append([img, maxf(secs, 0.02)])
			_mutex.unlock()
			count += 1
			prev_disposal = disposal
			prev_rect = Rect2i(ix, iy, iw, ih)
			disposal = 0
			transparent = -1
			delay = 10
	_finish()


func _lzw(data: PackedByteArray, min_code: int, count: int) -> PackedByteArray:
	var clear := 1 << min_code
	var eoi := clear + 1
	var code_size := min_code + 1
	var next_code := eoi + 1
	var prefix := PackedInt32Array()
	prefix.resize(4096)
	prefix.fill(-1)
	var suffix := PackedByteArray()
	suffix.resize(4096)
	for i in clear:
		suffix[i] = i
	var out := PackedByteArray()
	out.resize(count)
	var out_pos := 0
	var prev := -1
	var first := 0
	var bit_buf := 0
	var bit_cnt := 0
	var pos := 0
	var n := data.size()
	var stack := PackedByteArray()
	stack.resize(4097)
	while out_pos < count:
		while bit_cnt < code_size:
			if pos >= n:
				return out
			bit_buf |= int(data[pos]) << bit_cnt
			pos += 1
			bit_cnt += 8
		var code := bit_buf & ((1 << code_size) - 1)
		bit_buf >>= code_size
		bit_cnt -= code_size
		if code == clear:
			code_size = min_code + 1
			next_code = eoi + 1
			prev = -1
			continue
		if code == eoi:
			break
		if prev == -1:
			if code < clear:
				out[out_pos] = suffix[code]
			out_pos += 1
			prev = code
			first = code
			continue
		if code > next_code:
			return out   # corrupt data
		var in_code := code
		var sp := 0
		if code >= next_code:
			stack[sp] = first
			sp += 1
			code = prev
		while code >= clear:
			stack[sp] = suffix[code]
			sp += 1
			code = prefix[code]
		first = suffix[code]
		stack[sp] = first
		sp += 1
		while sp > 0:
			sp -= 1
			if out_pos < count:
				out[out_pos] = stack[sp]
				out_pos += 1
		if next_code < 4096:
			prefix[next_code] = prev
			suffix[next_code] = first
			next_code += 1
			if next_code == (1 << code_size) and code_size < 12:
				code_size += 1
		prev = in_code
	return out
