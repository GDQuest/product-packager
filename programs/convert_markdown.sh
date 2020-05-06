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

# Exit on error, unset variable, or failed pipe
set -euo pipefail

NAME="$(basename $0)"

ERROR_CSS_INVALID="Invalid CSS file. %s is not a valid file. Using default path %s."

CONTENT_DIRECTORY="content"
PDF_ENGINES="pdfroff, wkhtmltopdf, weasyprint, prince"

# Debug tools
FORMAT_NORMAL=$(tput sgr0)
FORMAT_BOLD=$(tput bold)

format_bold() {
	printf "%s%s%s" "$FORMAT_BOLD" "$*" "$FORMAT_NORMAL"
}

echo_help() {
	printf "Converts markdown documents to self-contained HTML or PDF files using Pandoc.

%s:
$NAME [Options]

%s:
No positional arguments.

%s:
-h/--help			 -- Display this help message.
-d/--dry-run		 -- Run without building any files and output debug information.
-o/--output-path	 -- Path to an existing directory path to output the rendered documents.
-t/--type			 -- Type of file to output, either html or pdf.
-p/--pdf-engine		 -- PDF rendering engine to use if --type is pdf.
Supported engines: $PDF_ENGINES
-c/--css			 -- path to the css file to use for rendering. Default: $css_file_path
" "$(format_bold Usage)" "$(format_bold Positional arguments)" "$(format_bold Options)"
	exit 0
}

# Outputs positional arguments to a temporary file `$temp_file`, see `main()`.
#
# Arguments:
# $@ -- The arguments passed to the program
parse_cli_arguments() {
	args=()
	# Convert long options to their short counterpart for getopts.
	for arg; do
		case "$arg" in
		--help) args+=(-h) ;;
		--dry-run) args+=(-d) ;;
		--output-path) args+=(-o) ;;
		--type) args+=(-t) ;;
		--pdf-engine) args+=(-p) ;;
		--css) args+=(-c) ;;
		*) args+=("$arg") ;;
		esac
	done

	set -- "${args[@]}"
	while getopts "h,d,o:,t:,p:,c:" OPTION; do
		case $OPTION in
		h)
			echo_help
			break
			;;
		d)
			is_dry_run=1
			;;
		o)
			output_path="$(realpath $OPTARG)"
			;;
		t)
			case "$2" in
			pdf | PDF)
				extension=pdf
				;;
			html | HTML | *)
				extension=html
				;;
			esac
			;;
		p)
			case "$OPTARG" in
			pdfroff | wkhtmltopdf | weasyprint | prince) pdf_engine="$OPTARG" ;;
			*) echo "Invalid PDF engine. Supported engines are: . Using default engine." ;;
			esac
			;;
		c)
			test -f "$OPTARG" && css_file_path=$(realpath "$OPTARG") || printf "$ERROR_CSS_INVALID" "$OPTARG" "$css_file_path"
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
		realpath $path >>$temp_file
	done
}

# Outputs the path to save a file to convert.
# Example: content/chapter-1/intro.md -> $output_path/chapter-1/intro.html
#
# Arguments:
# $1 -- path to a file to convert
# $2 -- output extension
get_out_path() {
	directory_name="$(basename "$(dirname "$1")")"
	out="$(basename "$1" | sed "s/\.md$/.$2/")"
	test "$directory_name" != "." && out="$directory_name/$out"
	test "$output_path" != "" && out="$output_path/$out"
	echo "$out"
}

# Outputs a document title from a file's path. Uses the file name converted to title case.
#
# Arguments:
# $1 -- path to a file
get_title() {
	name=$(basename "$1")
	name=${name/.md//}
	name=$(echo "$name" | sed 's/[0-9]*\.//')
	echo "${name[@]^}" | sed 's/[-_\/\\]/ /g' | sed 's/ *$//'
}

# Converts the file passed as an argument to a self-contained html or pdf document using pandoc.
#
# Arguments:
# $1 -- path to a file to convert
# $2 -- output extension
convert_markdown() {
	out=$(get_out_path "$1" "$2")
	title=$(get_title "$1")

	args="$1 --self-contained --toc --css \"$css_file_path\" --metadata pagetitle=\"$title\" --output \"$out\""
	test "$2" = "pdf" && args="$args --pdf-engine $pdf_engine"
	if test $is_dry_run -eq 0; then
		dir_input_file=$(dirname "$1")
		dir_output_file=$(dirname "$out")
		test ! -d "$dir_output_file" && mkdir --parents "$dir_output_file"
		cd "$dir_input_file"
		eval pandoc "$args"
		echo "Rendered document $out."
		cd $dir_start
	else
		echo "pandoc $args"
	fi

}

main() {
	local is_dry_run=0
	local temp_file=$(mktemp)

	local extension="html"

	local this_directory=$(dirname $(readlink -f "$0"))
	local css_file_path="$this_directory/css/pandoc.css"
	local output_path=""
	local pdf_engine="wkhtmltopdf"

	local dir_start=$(pwd)
	parse_cli_arguments "$@"
	while read filepath; do
		convert_markdown "$filepath" "$extension"
	done <"$temp_file"

	rm $temp_file
}

main "$@"
exit $?
