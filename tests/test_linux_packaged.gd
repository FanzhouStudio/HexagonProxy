extends SceneTree

func _init() -> void:
	assert(FileAccess.file_exists("res://third_party/linux_runtime/runtime.zip"))
	assert(not FileAccess.file_exists("res://third_party/linux_runtime/runtime.zip.tmp"))
	assert(FileAccess.file_exists("res://third_party/linux_runtime/Tuxee-LICENSE.txt"))
	var init := FileAccess.get_file_as_string("res://scripts/linux/init.sh")
	var guest := FileAccess.get_file_as_string("res://scripts/linux/guest-init.sh")
	assert(init.contains("/sbin/modprobe") and init.contains("e2fsck -fp"))
	assert(guest.contains("kill -KILL -1") and guest.contains("refusing forced poweroff"))
	assert(not init.contains("\r") and not guest.contains("\r"))
	var reader := ZIPReader.new()
	assert(reader.open("res://third_party/linux_runtime/runtime.zip") == OK)
	var manifest: Dictionary = JSON.parse_string(reader.read_file("manifest.json").get_string_from_utf8())
	for name in ["vmlinuz", "initramfs.gz", "rootfs.tar.gz", "qemu/qemu-system-x86_64.exe", "qemu/qemu-img.exe"]:
		assert(manifest.files.any(func(entry: Dictionary) -> bool: return entry.path == name), name)
	reader.close()
	print("PASS: exported offline bundle, licenses, current boot scripts and no temporary archive")
	quit()
