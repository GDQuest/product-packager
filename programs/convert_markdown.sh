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

NAME="convert_markdown"

CONTENT_DIRECTORY="content"

css_file_path="pandoc.css"
out_dir="dist"
# Use a supported pdf printing engine, the name of a program like weasyprint, wkhtmltopdf, or other.
pdf_engine="weasyprint"

convert_markdown_to_html() {
	directory_name="$(basename "$(dirname "$1")")"
	file_name="$(basename "$1" | sed 's/md$/html')"
	pandoc "$1" --self-contained --toc -N --css "$css_file_path" --output "$out_dir/$directory_name/$file_name"
}

convert_markdown_to_pdf() {
	directory_name="$(basename "$(dirname "$1")")"
	file_name="$(basename "$1" | sed 's/md$/pdf')"
	pandoc "$1" --self-contained --toc -N --css "$css_file_path" --pdf-engine "$pdf_engine" --output "$out_dir/$directory_name/$file_name"
}

echo_help() {
	printf 'Converts markdown documents to self-contained HTML or PDF files using Pandoc.

%s:
'"$NAME"' [Options]

%s:
No positional arguments.

%s:
-h/--help -- Display this help message.
-t/--type -- Type of file to output, either html or pdf.'
	"$(format_bold Usage)" "$(format_bold Positional arguments)" "$(format_bold Options)"
	exit 0
}

parse_cli_arguments() {
	arguments=$(getopt --name "$NAME" -o "h,t:" -l "help,type:" -- "$@")
	eval set -- "$arguments"
	while true; do
		case "$1" in
		-h | --help)
			echo_help
			break
			;;
		-t | --type)
			case "$2" in
			pdf | PDF)
				command=convert_markdown_to_pdf
				;;
			html | HTML | *)
				command=convert_markdown_to_html
				;;
			esac
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

	find "$CONTENT_DIRECTORY" -mindepth 1 -maxdepth 2 -iname "*.md" -type f -print0 -exec $command "{}" ";"
}

main "$@"
