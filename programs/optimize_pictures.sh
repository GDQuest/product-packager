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
#
# Description:
#
# Converts markdown documents to self-contained HTML or PDF files using Pandoc.

# Description:
#
# Optimize jpg and png image files in-place with lossy compression using imagemagick's mogrify and
# pngquant.

# Exit on error, unset variable, or failed pipe
set -euo pipefail

NAME="$(basename $0)"
ERROR_MAX_SIZE="Incorrect value for --size, it must be of the form 1000x1000. Turning auto-resize off."

# Debug tools
FORMAT_NORMAL=$(tput sgr0)
FORMAT_BOLD=$(tput bold)

format_bold() {
	printf "%s%s%s" "$FORMAT_BOLD" "$*" "$FORMAT_NORMAL"
}

echo_help() {
	set -x
	printf "Optimize jpg and png image files in-place with lossy compression using imagemagick
mogrify and pngquant.

%s:
$NAME [Options]

%s:
No positional arguments.

%s:
-h/--help        -- Display this help message.
-d/--dry-run     -- Run without building any files and output debug information.
-s/--size		 -- Any imagemagick Geometry that represents the output size of the image. For more
 information, see https://www.imagemagick.org/script/command-line-processing.php#geometry.
-i/--in-place    -- Optimize pictures in-place instead of to a new file.
-o/--output		 -- Path to a directory to output the files
" "$(format_bold Usage)" "$(format_bold Positional arguments)" "$(format_bold Options)"
	exit
}

# Parses command-line options using getopts
# outputs positional arguments to a temporary file `$temp_file`, see `main()`.
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
		--size) args+=(-s) ;;
		--in-place) args+=(-i) ;;
		--output) args+=(-o) ;;
		*) args+=("$arg") ;;
		esac
	done

	set -- "${args[@]}"
	while getopts "h,d,s:,i,o:" OPTION; do
		case $OPTION in
		h)
			echo_help
			;;
		d)
			is_dry_run=1
			;;
		s)
			size="$2"
			;;
		i)
			is_in_place=1
			;;
		o)
			output_directory="$OPTARG"
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
		test -f "$path" && echo $path >>$temp_file || continue
	done
}

# Resizes one png image with imagemagick and compresses it in-place with pngquant.
#
# Arguments:
# $1 -- the path to the file to convert.
compress_png() {
	convert "$1" -resize "$size" "$1"
	pngquant --quality 70-95 --force --ext .png "$1"
}
#
# Resizes and compresses one jpg image with imagemagick.
#
# Arguments:
# $1 -- the path to the file to convert.
compress_jpg() {
	convert "$1" -resize "$size"\> -sampling-factor 4:2:0 -strip -quality 85 -interlace JPEG -colorspace sRGB "$1"
}

# Compresses images.
#
# Gets a list of files to process from the temporary file `$temp_file`, a variable from `main()`.
# See `main()` for more information.
compress_lossy() {
	while read filepath; do
		directory=$(dirname "$filepath")
		filename=$(basename "$filepath")
		name="${filename%%.*}"
		ext="${filename##*.}"

		echo Processing "$filename"

		path_out="$output_directory"
		test "$path_out" = "" && path_out="$directory/$name-compressed.$ext" || path_out="$path_out/$filename"

		cp "$filepath" "$path_out"

		test "$ext" = jpg -o "$ext" = jpeg && compress_jpg "$path_out"
		test "$ext" = png && compress_png "$path_out"

		test $is_in_place -eq 1 && mv "$path_out" "$filepath"
	done <"$temp_file"
}

main() {
	local is_dry_run=0
	local temp_file=$(mktemp)

	local size="1000000x1000000"
	local is_in_place=0
	local output_directory=""

	parse_cli_arguments "$@"
	test "$output_directory" != "" -a ! -d "$output_directory" && mkdir -p "$output_directory"
	compress_lossy "$@"
	rm $temp_file
}

main "$@"
exit $?
