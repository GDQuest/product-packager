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
#
# ⚠ Warning: this tool optimizes the files in-place! Save your images before using this program.

# Exit on error, unset variable, or failed pipe
set -euo pipefail

NAME="optimize_pictures"
ERROR_MAX_SIZE="Incorrect value for --max-size, it must be of the form 1000x1000. Turning auto-resize off."

# Debug tools
FORMAT_NORMAL=$(tput sgr0)
FORMAT_BOLD=$(tput bold)

format_bold() {
	printf "%s%s%s" "$FORMAT_BOLD" "$*" "$FORMAT_NORMAL"
}

echo_help() {
	printf ' Optimize jpg and png image files in-place with lossy compression using imagemagick
mogrify and pngquant.

%s:
'"$NAME"' [Options]

%s:
No positional arguments.

%s:
-h/--help     -- Display this help message.
-m/--max-size -- Downsize pictures larger than this size in pixels. Should be of the form 1000x1000.
 Preserves the aspect ratio of the original image and fits the image in the maximum size.'
	"$(format_bold Usage)" "$(format_bold Positional arguments)" "$(format_bold Options)"
	exit 0
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
		--max-size) args+=(-t) ;;
		*) args+=("$arg") ;;
		esac
	done

	set -- "${args[@]}"
	while getopts "h,d,m:" OPTION; do
		case $OPTION in
		h)
			echo_help
			break
			;;
		d)
			is_dry_run=1
			;;
		m)
			echo "$2" | grep -E "[0-9]+x[0-9]+" && max_size="$2" || echo "$ERROR_MAX_SIZE"
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

# Compresses and overwrites images using imagemagick's `mogrify` program.
#
# Gets a list of files to process from the temporary file `$temp_file`, a variable from `main()`.
# See `main()` for more information.
compress_lossy() {
	while read filepath; do
		mogrify "$filepath" -resize "$max_size"\>
		echo "$filepath" | grep -Ei "jpe?g$" && mogrify "$filepath" -sampling-factor 4:2:0 -strip -quality
		85 -interlace JPEG -colorspace sRGB
		echo "$filepath" | grep -Ei "png$" && pngquant -f --ext .png --quality 70-95 "$filepath"
	done <"$temp_file"
}

main() {
	local is_dry_run=0

	local max_size="1000000x1000000"
	local temp_file=$(mktemp)

	filepaths=$(parse_cli_arguments "$@")
	test $? -eq 0 && compress_lossy "$@"
	exit $?
}

main "$@"
