extends RefCounted
## IMA ADPCM, 4 bits per sample: the small, dependency-free codec the room uses to send sound between
## players (music from the host's speakers, later voices). About a quarter of PCM16, no licence, no
## library, decodes in a few lines. Each packet carries its own predictor state so a lost packet only
## loses itself. Stereo is coded as two independent channels.

const STEP := [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
	157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707,
	1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
	15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
const INDEX := [-1, -1, -1, -1, 2, 4, 6, 8]


class Coder:
	var pred := 0
	var idx := 0

	func encode(sample: int) -> int:
		var step: int = STEP[idx]
		var diff := sample - pred
		var code := 0
		if diff < 0:
			code = 8
			diff = -diff
		var d := step >> 3
		if diff >= step:
			code |= 4
			diff -= step
			d += step
		if diff >= step >> 1:
			code |= 2
			diff -= step >> 1
			d += step >> 1
		if diff >= step >> 2:
			code |= 1
			d += step >> 2
		pred = clampi(pred + (-d if code & 8 else d), -32768, 32767)
		idx = clampi(idx + INDEX[code & 7], 0, 88)
		return code

	func decode(code: int) -> int:
		var step: int = STEP[idx]
		var d := step >> 3
		if code & 4:
			d += step
		if code & 2:
			d += step >> 1
		if code & 1:
			d += step >> 2
		pred = clampi(pred + (-d if code & 8 else d), -32768, 32767)
		idx = clampi(idx + INDEX[code & 7], 0, 88)
		return pred


# frames: PackedVector2Array of stereo samples in -1..1. Returns one packet:
# [u16 count][i16 predL][u8 idxL][i16 predR][u8 idxR][nibbles L...][nibbles R...]
static func encode(frames: PackedVector2Array) -> PackedByteArray:
	var n := frames.size()
	var l := Coder.new()
	var r := Coder.new()
	# prime the predictors on the first sample so the packet starts close to the signal
	if n > 0:
		l.pred = int(clampf(frames[0].x, -1.0, 1.0) * 32767.0)
		r.pred = int(clampf(frames[0].y, -1.0, 1.0) * 32767.0)
	var out := PackedByteArray()
	out.resize(8 + ((n + 1) / 2) * 2)
	out.encode_u16(0, n)
	out.encode_s16(2, l.pred)
	out[4] = 0
	out.encode_s16(5, r.pred)
	out[7] = 0
	var half := (n + 1) / 2
	for i in n:
		var cl := l.encode(int(clampf(frames[i].x, -1.0, 1.0) * 32767.0))
		var cr := r.encode(int(clampf(frames[i].y, -1.0, 1.0) * 32767.0))
		var bi := 8 + i / 2
		var sh := 0 if i % 2 == 0 else 4
		out[bi] |= cl << sh
		out[bi + half] |= cr << sh
	return out


static func decode(packet: PackedByteArray) -> PackedVector2Array:
	var out := PackedVector2Array()
	if packet.size() < 8:
		return out
	var n := packet.decode_u16(0)
	var half := (n + 1) / 2
	if n > 8192 or packet.size() < 8 + half * 2:
		return out
	var l := Coder.new()
	var r := Coder.new()
	l.pred = packet.decode_s16(2)
	l.idx = clampi(packet[4], 0, 88)
	r.pred = packet.decode_s16(5)
	r.idx = clampi(packet[7], 0, 88)
	out.resize(n)
	for i in n:
		var bi := 8 + i / 2
		var sh := 0 if i % 2 == 0 else 4
		var sl := l.decode((packet[bi] >> sh) & 15)
		var sr := r.decode((packet[bi + half] >> sh) & 15)
		out[i] = Vector2(sl / 32768.0, sr / 32768.0)
	return out
