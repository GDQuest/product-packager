#!/usr/bin/env sh
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

NAME="optimize_videos"
ERROR_RESIZE="Incorrect value for --resize. Turning resize off."

scale=""
no_audio=0

# SOURCING FILES
. ./lib/utils.sh

echo_help() {
	printf 'Compress videos to h264 MP4 with ffmpeg.
⚠ Warning: this program overwrites the source videos! Create a backup of your files before running it.

%s:
'"$NAME"' [Options]

%s:
No positional arguments.

%s:
-h/--help         -- Display this help message.
-r/--resize size  -- Resize the video to this size using the scale filter. The size must be of a form
 supported by the ffmpeg scale filter. For example, 1280:720 for a 720p size or iw/2:-1 to divide
 the original video size by two. See https://trac.ffmpeg.org/wiki/Scaling for more information.
-n/--no-audio     -- Remove all audio from the output videos.'
	"$(format_bold Usage)" "$(format_bold Positional arguments)" "$(format_bold Options)"
	exit 0
}

parse_cli_arguments() {
	arguments=$(getopt --name "$NAME" -o "h,r,n:" -l "help,resize:,no-audio" -- "$@")
	eval set -- "$arguments"
	while true; do
		case "$1" in
		-h | --help)
			echo_help
			break
			;;
		-r | --resize)
			echo "$2" | grep -E ".+:.+" && scale="$2" || echo "$ERROR_RESIZE"
			shift 2
			;;
		-n | --no-audio)
			no_audio=1
			shift
			;;
		--)
			shift
			break
			;;
		esac
	done
}

# Compresses and overwrites
# Arguments:
# $@: list of paths to video files
compress_video() {
	command="ffmpeg -hwaccel auto -y -v quiet -i %s -c:v libx264 -crf 20 -preset slow"
	test $no_audio -eq 1 && command="$command -an" || command="$command -c:a aac -b:a 320k"
	test scale != "" && command="$command -filter \"scale=$scale\""

	for filepath in "$@"; do
		filename=$(basename "$filepath")
		path_temp="$(dirname "$filepath")/temp_$(echo "$filename" | sed 's/\.[A-Za-z0-9]+$/.mp4/')"
		path_out="$(echo $path_temp | sed 's/temp_//')"
		ffmpeg_command=$(printf "$command %s" "$filepath" "$path_temp")
		command "$ffmpeg_command"
		mv -v "$path_temp" "$path_out"
	done
}

main() {
	parse_cli_arguments "$@"
	test $? -eq 0 && compress_lossy "$@"
	exit $?
}

main "$@"
