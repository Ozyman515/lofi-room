extends RefCounted
## Pictures that come from other players (tape frames, the poster, comic pages) are checked before they are
## unpacked: a JPEG says how big it is in its header, and a faked header claiming a gigantic picture would make
## the decoder grab gigabytes of memory and crash the room. So the size is read first, and only pictures that
## fit are decoded at all.


# width and height from a JPEG's header (its first "start of frame" marker), or (0, 0) if it isn't a sane JPEG
static func jpeg_size(b: PackedByteArray) -> Vector2i:
	var n := b.size()
	if n < 4 or b[0] != 0xFF or b[1] != 0xD8:
		return Vector2i.ZERO
	var i := 2
	while i + 4 <= n:
		if b[i] != 0xFF:
			return Vector2i.ZERO
		var m := b[i + 1]
		if m == 0xFF:                              # padding
			i += 1
			continue
		if m == 0xD8 or m == 0x01 or (m >= 0xD0 and m <= 0xD7):
			i += 2                                 # markers with no length
			continue
		if m == 0xD9 or m == 0xDA:
			return Vector2i.ZERO                   # image data (or the end) before any size: not trusted
		var seg := (b[i + 2] << 8) | b[i + 3]
		if seg < 2:
			return Vector2i.ZERO
		# SOF0..SOF15, except DHT (C4), JPG (C8) and DAC (CC)
		if m >= 0xC0 and m <= 0xCF and m != 0xC4 and m != 0xC8 and m != 0xCC:
			if i + 9 > n:
				return Vector2i.ZERO
			return Vector2i((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6])
		i += 2 + seg
	return Vector2i.ZERO


# the picture, or null if it isn't a JPEG at most max_side pixels on each side
static func jpeg(b: PackedByteArray, max_side: int) -> Image:
	var s := jpeg_size(b)
	if s.x <= 0 or s.y <= 0 or s.x > max_side or s.y > max_side:
		return null
	var img := Image.new()
	if img.load_jpg_from_buffer(b) != OK or img.get_width() > max_side or img.get_height() > max_side:
		return null
	return img
