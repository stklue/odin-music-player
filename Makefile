run:
	odin build track -show-timings -debug -out:bin/debug/player.exe -o:speed
release:
	odin build track -show-timings -out:bin/release/player.exe -o:speed