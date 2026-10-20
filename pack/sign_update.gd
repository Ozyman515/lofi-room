## Signs update.json with the private key. Run after make_update.py, from the project folder:
##   godot --headless -s pack/sign_update.gd -- /somewhere/safe/update_key.pem
## Writes update.json.sig (base64 of an RSA PKCS#1 v1.5 signature over the SHA-256 of update.json).
## The room checks it against update_key.pub before it installs anything; without it, no update.
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: godot --headless -s pack/sign_update.gd -- <private key path>")
		quit(1)
		return
	var key := CryptoKey.new()
	if key.load(args[0], false) != OK:
		push_error("could not read the private key " + args[0])
		quit(1)
		return
	var body := FileAccess.get_file_as_bytes("res://update.json")
	if body.is_empty():
		push_error("update.json is missing: run make_update.py first")
		quit(1)
		return
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	var sig := Crypto.new().sign(HashingContext.HASH_SHA256, ctx.finish(), key)
	var f := FileAccess.open("res://update.json.sig", FileAccess.WRITE)
	f.store_string(Marshalls.raw_to_base64(sig) + "\n")
	f.close()
	# make sure it verifies with the public half that ships
	var pub := CryptoKey.new()
	if pub.load("res://update_key.pub", true) != OK:
		push_error("update_key.pub is missing from the project")
		quit(1)
		return
	var ctx2 := HashingContext.new()
	ctx2.start(HashingContext.HASH_SHA256)
	ctx2.update(body)
	if not Crypto.new().verify(HashingContext.HASH_SHA256, ctx2.finish(), sig, pub):
		push_error("the signature does not verify with update_key.pub: wrong key?")
		quit(1)
		return
	print("signed update.json (", body.size(), " bytes) -> update.json.sig")
	quit()
