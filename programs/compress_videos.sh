#!/usr/bin/env sh

# Compares the content of the $dir_dist/src and $dir_dist/compressed directories and returns a list
# of files missing in the compressed directory.
find_videos_to_compress() {
	path_dist="$dir_project/$dir_dist"
	diff "$path_dist/src" "$path_dist/compressed" | grep -E "^Only in" | sed -n 's/^Only in //p' | cut -d" " -f1-2
}

# Arguments:
# $@: list of paths to video files
videos_compress_ffmpeg() {
	for path in "$@"; do
		directory=$(dirname "$path")
		file=$(basename "$path")
		name=$(echo "$file" | rev | cut -d. -f2- | rev)
		path_out="$directory"/"$name"'-compressed.mp4'
		test $is_dry_run -eq 0 && ffmpeg -i "$path" -c:a copy -c:v h264_nvenc -preset slow -qp 20 "$path_out"
		echo "$path_out"
	done
}
