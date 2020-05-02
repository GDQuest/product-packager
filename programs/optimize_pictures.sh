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

NAME="optimize_pictures"
ERROR_MAX_SIZE="Incorrect value for --max-size, it must be of the form 1000x1000. Turning auto-resize off."

max_size="1000000x1000000"

compress_lossy() {
	for file in "$@"; do
		mogrify "$file" -resize "$max_size"\>
		echo "$file" | grep -Ei "jpe?g$" && mogrify "$file" -sampling-factor 4:2:0 -strip -quality
		85 -interlace JPEG -colorspace sRGB
		echo "$file" | grep -Ei "png$" && pngquant -f --ext .png --quality 70-95 "$file"
	done
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

parse_cli_arguments() {
	arguments=$(getopt --name "$NAME" -o "h,m:" -l "help,max-size:" -- "$@")
	eval set -- "$arguments"
	while true; do
		case "$1" in
		-h | --help)
			echo_help
			break
			;;
		-m | --max-size)
			echo "$2" | grep -E "[0-9]+x[0-9]+" && max_size="$2" || echo "$ERROR_MAX_SIZE"
			shift 2
			;;
		--)
			shift
			break
			;;
		esac
	done
}

main() {
	parse_cli_arguments "$@"
	test $? -eq 0 && compress_lossy "$@"
	exit $?
}

main "$@"
