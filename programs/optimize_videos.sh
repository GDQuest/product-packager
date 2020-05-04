#!/usr/bin/env bash
#
# Copyright (C) 2020 by Nathan Lovato and contributors
#
# This file is part of GDQuest product packager.
#
# GDQuest product packager is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation, either
# version 3 of the License, or (at your option) any later version.
#
# GDQuest product packager is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with GDQuest product
# packager. If not, see <https://www.gnu.org/licenses/>.

# Description:
#
# Compress videos to h264 mp4 with ffmpeg.
#
# ⚠ Warning: this tool overwrites the source videos! Backup your videos before using this program.

# Exit on error, unset variable, or failed pipe
set -euo pipefail

NAME="optimize_videos.sh"
ERROR_RESIZE="Incorrect value for --resize. Turning resize off."
TUNE_OPTIONS="film, animation, grain, stillimage"

scale=""
tune=""
no_audio=0

# Debug tools
FORMAT_NORMAL=$(tput sgr0)
FORMAT_BOLD=$(tput bold)

is_dry_run=0

format_bold() {
	printf "%s%s%s" "$FORMAT_BOLD" "$*" "$FORMAT_NORMAL"
}

echo_help() {
	printf 'Compress videos to h264 MP4 with ffmpeg.
⚠ Warning: this program overwrites the source videos! Create a backup of your files before running it.

%s:
'"$NAME"' [Options]

%s:
No positional arguments.

%s:
-h/--help         -- Display this help message.
-t/--tune         -- Tune option for the ffmpeg output. Should be one of '"$TUNE_OPTIONS"'
-r/--resize size  -- Resize the video to this size using the scale filter. The size must be of a form
 supported by the ffmpeg scale filter. For example, 1280:720 for a 720p size or iw/2:-1 to divide
 the original video size by two. See https://trac.ffmpeg.org/wiki/Scaling for more information.
-n/--no-audio     -- Remove all audio from the output videos.' "$(format_bold "Usage")" "$(format_bold "Positional arguments")" "$(format_bold "Options")"
	exit 0
}

parse_cli_arguments() {
	arguments=$(getopt --name "$NAME" -o "h,d,r:,n,t:" -l "help,dry-run,resize:,no-audio,tune:" -- "$@")
	eval set -- "$arguments"
	while true; do
		case "$1" in
		-h | --help)
			echo_help
			break
			;;
		-d | --dry-run)
			is_dry_run=1
			shift
			;;
		-r | --resize)
			echo "$2" | grep -Eq ".+:.+" && scale="$2" || echo "$ERROR_RESIZE"
			shift 2
			;;
		-n | --no-audio)
			no_audio=1
			shift
			;;
		-t | --tune)
			case "$2" in
			film | animation | grain | stillimage) tune="$2" ;;
			*)
				echo "Incorrect ffmpeg -tune option. Should be one of: $TUNE_OPTIONS"
				exit 1
				;;
			esac
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo "There was an error"
			exit 1
			;;
		esac
	done
	for i in "$@"; do
		echo "$i"
	done
}

# Compresses and overwrites
# Arguments:
# $@: list of paths to video files
compress_videos() {
	args="-hwaccel auto -y -v quiet -i \"%s\" -c:v libx264 -crf 20 -preset slow"
	test $no_audio -eq 1 && args="$args -an" || args="$args -c:a aac -b:a 320k"
	test "$scale" != "" && args="$args -filter \"scale=$scale\""
	test "$tune" != "" && args="$args -tune $tune"

	while read -r filepath; do
		echo Processing video "$filepath"
		ffmpeg_command=$(printf "ffmpeg $args \"%s\"" "$filepath" "$path_temp")
		path_temp=${filepath%%.*}_temp.mp4
		path_out=${path_temp//_temp/}
		test $is_dry_run -eq 0 && eval "$ffmpeg_command" || echo "$ffmpeg_command"
		test $is_dry_run -eq 0 && mv -v "$path_temp" "$path_out" || echo Moving "$path_temp" to "$path_out"
	done <"$1"
}

main() {
	temp_file=$(mktemp)
	parse_cli_arguments "$@" >"$temp_file"
	compress_videos "$temp_file"
	exit $?
}

main "$@"
