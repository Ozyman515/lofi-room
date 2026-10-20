## Makes the update-signing key pair. Run ONCE, from the project folder:
##   godot --headless -s pack/keygen.gd -- /somewhere/safe/update_key.pem
## The private key goes to that path (keep it out of the repo and backed up); the public half is written
## to update_key.pub in the project, where every copy of the room reads it.
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: godot --headless -s pack/keygen.gd -- <private key path>")
		quit(1)
		return
	var key := Crypto.new().generate_rsa(3072)
	var err := key.save(args[0], false)
	if err != OK:
		push_error("could not write the private key to " + args[0])
		quit(1)
		return
	key.save("res://update_key.pub", true)
	print("private key: ", args[0])
	print("public key:  update_key.pub (commit this one)")
	quit()
