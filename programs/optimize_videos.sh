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

set -euo pipefail

NAME="$(basename $0)"
ERROR_RESIZE="Incorrect value for --resize. Turning resize off."
TUNE_OPTIONS="film, animation, grain, stillimage"

# Debug tools
FORMAT_NORMAL=$(tput sgr0)
FORMAT_BOLD=$(tput bold)

format_bold() {
	printf "%s%s%s" "$FORMAT_BOLD" "$*" "$FORMAT_NORMAL"
}

echo_help() {
	printf "Compress videos to h264 MP4 with ffmpeg.
⚠ Warning: this program overwrites the source videos! Create a backup of your files before running it.

%s:
$NAME [Options]

%s:
No positional arguments.

%s:
-h/--help            -- Display this help message.
-d/--dry-run         -- Run without building any files and output debug information.
-t/--tune            -- Tune option for the ffmpeg output. Should be one of $TUNE_OPTIONS
-r/--resize size     -- Resize the video to this size using the scale filter. The size must be of a
 form supported by the ffmpeg scale filter. For example, 1280:720 for a 720p size or iw/2:-1 to
 divide the original video size by two. See https://trac.ffmpeg.org/wiki/Scaling for more
 information.
-n/--no-audio        -- Remove all audio from the output videos.
-u/--use-nvenc       -- Use NVidia NVENC for encoding.
" "$(format_bold "Usage")" "$(format_bold "Positional arguments")" "$(format_bold "Options")"
	exit
}

# Parses command-line options using getopts
# Outputs positional arguments to a temporary file `$temp_file`, see `main()`.
#
# Arguments:
# $@ -- The arguments passed to the program
parse_cli_arguments() {
	args=()
	# Handle long options
	for arg; do
		case "$arg" in
		--help) args+=(-h) ;;
		--dry-run) args+=(-d) ;;
		--tune) args+=(-t) ;;
		--resize) args+=(-r) ;;
		--no-audio) args+=(-n) ;;
		--use-nvenc) args+=(-u) ;;
		*) args+=("$arg") ;;
		esac
	done

	set -- "${args[@]}"
	while getopts "h,d,r:,n,t:,u" OPTION; do
		case $OPTION in
		h)
			echo_help
			;;
		d)
			is_dry_run=1
			;;
		r)
			echo "$OPTARG" | grep -Eq ".+[:x].+" && scale="\"$OPTARG\"" || echo "$ERROR_RESIZE"
			;;
		n)
			no_audio=1
			;;
		u)
			use_nvenc=1
			;;
		t)
			case "$OPTARG" in
			film | animation | grain | stillimage) tune="$OPTARG" ;;
			*)
				echo "Incorrect ffmpeg -tune option. Should be one of: $TUNE_OPTIONS"
				exit 1
				;;
			esac
			;;
		--)
			break
			;;
		\?)
			echo "Invalid option: $OPTION" 1>&2
			;;
		:)
			echo "Invalid option: $OPTION requires an argument" 1>&2
			;;
		*)
			echo "There was an error: option '$OPTION' with value $OPTARG"
			exit 1
			;;
		esac
	done
	shift $((OPTIND - 1))
	for path in "$@"; do
		echo $path >>$temp_file
	done
}

# Compresses and overwrites videos using ffmpeg, using variables from `main()`.
#
# Gets a list of files to process from the temporary file `$temp_file`, a variable from `main()`.
# See `main()` for more information.
compress_videos() {
	args="-hwaccel auto -y -v quiet -i \"%s\""
	test $use_nvenc -eq 0 && args="$args -c:v libx264 -crf 20 -preset slow" || args="$args -c:v h264_nvenc -qp 20 -preset slow"
	test $no_audio -eq 1 && args="$args -an" || args="$args -c:a aac -b:a 320k"
	test "$scale" != "" && args="$args -filter \"scale=$scale\""
	test "$tune" != "" && args="$args -tune $tune"

	while read filepath; do
		echo Processing video "$filepath"

		path_temp=${filepath%%.*}"_temp.mp4"
		path_out=${path_temp//_temp/}
		args_current=$(printf -- "$args \"%s\"" "$filepath" "$path_temp")

		if test $is_dry_run -eq 0; then
			eval "ffmpeg $args_current </dev/null"
			mv -v "$path_temp" "$path_out"
		else
			echo ffmpeg $args_current
			echo Moving "$path_temp" to "$path_out"
		fi
	done <"$temp_file"
}

main() {
	local is_dry_run=0
	local temp_file=$(mktemp)

	local scale=""
	local tune=""
	local no_audio=0
	local use_nvenc=0

	parse_cli_arguments "$@"
	compress_videos "$temp_file"
	rm $temp_file
	exit $?
}

main "$@"
