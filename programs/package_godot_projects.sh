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
# Finds, copies, and cleans up, and zips Godot projects to a given directory.

set -euo pipefail

# Debug tools
NAME="$(basename $0)"
FORMAT_NORMAL=$(tput sgr0)
FORMAT_BOLD=$(tput bold)

format_bold() {
	printf "%s%s%s" "$FORMAT_BOLD" "$*" "$FORMAT_NORMAL"
}

# Outputs the strings converted to lowercase filenames, with spaces replaced by hyphens.
#
# Arguments:
# $@ - a list of strings to process
strings_to_filename() {
	for string in "$@"; do
		echo "$string " | tr "[:upper:]" "[:lower:]" | tr --squeeze-repeats " " "-"
	done
}

echo_help() {
	printf 'Finds, copies, and cleans up, and zips Godot projects to a given directory.

%s:
'"$NAME"' [Options] $godot_directory $output_directory

%s:
$godot_directory	 -- Parent directory from which the program finds Godot projects.
$output_directory	 -- Directory to output the clean Godot projects and optional zip archive.

%s:
-h/--help			 -- Display this help message.
-d/--dry-run		 -- Run without building any files and output debug information.
-n/--no-zip			 -- Do not create a zip archive from the Godot projects, keep the cleaned directories instead.
-t/--title			 -- Name to use for the output directory or zip archive.
' "$(format_bold "Usage")" "$(format_bold "Positional arguments")" "$(format_bold "Options")"
	exit 0
}

# Parses command-line options using getopts
# Arguments:
# $@ -- The arguments passed to the program
parse_cli_arguments() {
	args=()
	# Handle long options
	for arg; do
		case "$arg" in
		--help) args+=(-h) ;;
		--dry-run) args+=(-d) ;;
		--no-zip) args+=(-n) ;;
		--title) args+=(-t) ;;
		*) args+=("$arg") ;;
		esac
	done

	set -- "${args[@]}"
	while getopts "h,d,r:,n,t:" OPTION; do
		case $OPTION in
		h)
			echo_help
			break
			;;
		d)
			is_dry_run=1
			;;
		n)
			do_zip=0
			;;
		t)
			out_file_name="$OPTARG"
			;;
		--) break ;;
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
	dir_godot="$1"
	dir_dist="$2"
}

package_godot_projects() {
	dir_export="$dir_dist/$out_file_name"

	temp_file=$(mktemp)
	find "$dir_godot" -not -path "./tutorial" -not -path "./dist" -type f -name project.godot -exec dirname {} \; >>$temp_file
	dirs_count=$(wc -l <$temp_file)
	printf "Found %s godot projects." "$dirs_count"
	test $dirs_count -eq 0 && return 0

	if test $is_dry_run -eq 0; then
		test ! -d "$dir_export" && mkdir -p "$dir_export"
		test ! -d "$dir_dist" && mkdir -p "$dir_dist"
	fi

	while read dirpath; do
		printf "Copying project %s to %s.\n" "$(basename "$dirpath")" "$dir_export"
		test $is_dry_run -eq 0 && cp -r "$dirpath" "$dir_export"
	done <"$temp_file"

	echo "Removing .import directories..."
	test $is_dry_run -eq 0 && rm -rf $(find . -path dist -type d -name .import)
	echo "Done."

	if test $do_zip -eq 1; then
		if test $is_dry_run -eq 0; then
			archive_name="$out_file_name.zip"

			# cd to the dist directory so the zip file doesn't contain it.
			dir_start=$(pwd)
			cd $dir_dist
			zip -r "$archive_name" *
			cd $dir_start

			rm -rf "$dir_export"
		fi
		echo "Removing the $dir_export directory..."
	else
		echo "Moving directory $dir_export to $dir_dist."
		test $is_dry_run -eq 0 && mv -rf "$dir_export" "$dir_dist"
	fi
	echo "Done."
}

main() {
	local is_dry_run=0

	local out_file_name="godot"
	local dir_godot=""
	local dir_dist=""
	local do_zip=1

	parse_cli_arguments "$@"
	package_godot_projects
}

main "$@"
exit $?
