extends Node
## Only one copy of the room at a time (PC). The first copy listens on a fixed local port; a second copy that
## finds the port taken asks whoever is there "are you the room?", and if the answer is yes it brings that
## window to the front and closes itself before building anything. If something else owns the port (no
## answer), the room starts anyway, so a stray program can never lock you out.
## A copy started by the room's own restart (lofi_relaunch=...) is let through: it waits for the old copy to
## close and then takes the port over. The headset has no second copies, and LOFI_MULTI=1 allows several
## (two-player tests on one PC).

const Plat := preload("res://platform.gd")
const PORT := 47853
const HELLO := "lofi-room?"
const ANSWER := "lofi-room"

signal poked                                 # another copy tried to start

var _server: TCPServer
var _clients: Array[StreamPeerTCP] = []
var _retry_t := 0.0


# true = carry on starting; false = another room is open (it has been told to come to the front)
func claim() -> bool:
	if Plat.is_android() or OS.get_environment("LOFI_MULTI") == "1":
		return true
	if _listen():
		return true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("lofi_relaunch="):
			return true                          # the restart: take the port once the old copy has gone
	return not _other_room_answers()


func _listen() -> bool:
	var s := TCPServer.new()
	if s.listen(PORT, "127.0.0.1") != OK:
		return false
	_server = s
	return true


func _other_room_answers() -> bool:
	var c := StreamPeerTCP.new()
	if c.connect_to_host("127.0.0.1", PORT) != OK:
		return false
	var t0 := Time.get_ticks_msec()
	var sent := false
	var got := ""
	while Time.get_ticks_msec() - t0 < 1500:
		c.poll()
		var st := c.get_status()
		if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
			return false
		if st == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				c.put_data((HELLO + "\n").to_utf8_buffer())
				sent = true
			var n := c.get_available_bytes()
			if n > 0:
				got += c.get_utf8_string(n)
				if got.strip_edges() == ANSWER:
					c.disconnect_from_host()
					return true
		OS.delay_msec(20)
	c.disconnect_from_host()
	return false


func _process(delta: float) -> void:
	if _server == null:
		if Plat.is_android() or OS.get_environment("LOFI_MULTI") == "1":
			set_process(false)
			return
		_retry_t -= delta                        # (after a restart: the old copy is closing)
		if _retry_t <= 0.0:
			_retry_t = 1.0
			_listen()
		return
	while _server.is_connection_available():
		var c := _server.take_connection()
		if c != null:
			_clients.append(c)
	for c: StreamPeerTCP in _clients.duplicate():
		c.poll()
		if c.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(c)
			continue
		var n := c.get_available_bytes()
		if n > 0 and c.get_utf8_string(n).strip_edges() == HELLO:
			c.put_data((ANSWER + "\n").to_utf8_buffer())
			poked.emit()


func _exit_tree() -> void:
	if _server != null:
		_server.stop()
