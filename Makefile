run:
	odin build track -show-timings -debug -out:bin/debug/player.exe
release:
	odin build track -show-timings -out:bin/release/player.exe -o:speed