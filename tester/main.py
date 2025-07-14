import os
from mutagen import File as MutagenFile
import time

# Set your root folder
ROOT_FOLDER = "C:/Users/St.Klue/Music"

# Extensions to include
# MEDIA_EXTENSIONS = (".mp3", ".flac", ".wav", ".ogg")
MEDIA_EXTENSIONS = (".mp3")

# Where we'll store metadata
library = []

# Start timing
start_time = time.time()

# Start scanning
print(f"📂 Scanning folder: {ROOT_FOLDER}")
file_count = 0

for dirpath, dirnames, filenames in os.walk(ROOT_FOLDER):
    for filename in filenames:
        if filename.lower().endswith(MEDIA_EXTENSIONS):
            file_count += 1
            full_path = os.path.join(dirpath, filename)
            
            try:
                audio = MutagenFile(full_path, easy=True)
                metadata = {
                    "path": full_path,
                    "title": audio.get("title", ["Unknown"])[0],
                    "artist": audio.get("artist", ["Unknown"])[0],
                    "album": audio.get("album", ["Unknown"])[0],
                }
            except Exception:
                metadata = {
                    "path": full_path,
                    "title": "Error reading",
                    "artist": "Error",
                    "album": "Error",
                }

            library.append(metadata)

# End timing
end_time = time.time()
duration = end_time - start_time

# Results
print("\n✅ Scan complete!")
print(f"🎵 Total media files found: {file_count}")
print(f"⏱️  Time taken: {duration:.2f} seconds\n")

# Preview first 5 entries
for entry in library[:5]:
    print(f"{entry['artist']} - {entry['title']} ({entry['album']})")
