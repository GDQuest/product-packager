#!/usr/bin/env sh
#
# Description:
#
# Finds and moves rendered content files from the $dir_content directory to the $dir_dist directory.
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

# Use semantic versioning with an optional hyphen-separated suffix, e.g. 0.3.2 or 1.0.0-dev
VERSION="0.1.0-dev"

# USER CONFIGURATION
NAME="move_content_files_to_dist"

dir_dist="dist"
dir_content="content"
dir_project=

# Debug
is_dry_run=1
do_suppress_output=0
verbosity=0
test $is_dry_run -ne 0 && verbosity=99

# SOURCING FILES
. ./lib/utils

echo_help() {
	test
	printf 'Finds and moves rendered content files from the content directory to the dist or output directory.

%s:
'"$NAME"' $path_to_project [Options]

Positional arguments, like $path_to_project, must come before option flags.

%s:
$path_to_project (required) -- path to your project directory. It must contain a sub-directory named '"$dir_content"' for the program
to run.

%s:
-h/--help             -- Display this help message.
-o/--output-directory -- Directory path to put the output. Default: '"$dir_dist"'
-i/--input-directory  -- Directory path into which to search the content. Default: '"$dir_content"'
' "$(format_bold Usage)" "$(format_bold Positional arguments)" "$(format_bold Options)"
	exit 0
}

parse_cli_arguments() {
	test "$1" = "-h" -o "$1" = "--help" && echo_help
	dir_project=$1
	shift
	test -d "$dir_project" || echo_error "$dir_project does not exist. The program needs a valid project directory path to run. Exiting." && exit 1

	arguments=$(getopt --name "$NAME" -o "h,o:,i:" -l "help,output-directory:,input-directory:" -- "$@")
	eval set -- "$arguments"
	while true; do
		case "$1" in
		-h | --help)
			echo_help
			shift
			;;
		-o | --output-directory)
			test -d "$dir_dist" && dir_dist=$2 || printf "The directory %s does not exist. Exiting." "$dir_dist" && exit 1
			shift 2
			;;
		-i | --input-directory)
			test -d "$dir_content" && dir_content=$2 || printf "The directory %s does not exist. Exiting." "$dir_content" && exit 1
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo_error "parse_cli_arguments" "Missing option flag. Try '$NAME --help' for more information"
			exit 1
			;;
		esac
	done
}

# Finds rendered files or files to output in the $dir_content directory and outputs it to the
# $dir_dist directory, replicating the chapters' structure.
# Warning: the function uses 'eval' with 'find' to find files by extensions.
#
# Arguments:
# -- optional list of file extensions like "pdf html mp4" to filter the files to move.
move_output_files() {
	for path_chapter in $(find "$dir_content" -maxdepth 1 -mindepth 1 -type d); do
		dist_directory=$dir_dist/$(basename "$path_chapter")

		find_patterns=$(test "$@" && echo "$@" | sed -E 's/(\w+)/-iname "*.\1" -o/g' | sed 's/\ -o$//')
		find_command="find $path_chapter -maxdepth 1 -mindepth 1"
		# TODO: Check that this notation works
		test "$find_patterns" && find_command="$find_command -type f \( $find_patterns \)"
		files=$(eval "$find_command")
		files_string=$(printf "\- %s\n" "${files}")

		echo_debug 1 "Found" "$(echo "$files_string" | wc -l)" "files to copy:\n" "$files_string"
		if test "$is_dry_run" -eq 0; then
			test -d "$dist_directory" || mkdir -p "$dist_directory"
			mv -v --backup --force "$files" "$dist_directory"
		fi
	done
}

main() {
	test "$(echo $VERSION | cut -d- -f2)" = "dev" &&
		printf "%s: this is a development version of the program. It is not suitable for production use.\n" "$(format_bold Warning)"

	test "$@" = "" && echo_error "main" "Missing required arguments.\n" && echo_help

	parse_cli_arguments "$@"
	test $? -ne 0 && echo_error "main" "There was an error parsing the command line arguments. Exiting." && exit $?

	test -d "$dir_project/$dir_content" ||
		printf "Missing %s directory. The program needs %s to exist to work. Exiting." "$(format_italic "$dir_content")" "$(format_italic "$dir_project/$dir_content")" && exit 1
	exit 0
}

main "$@"
exit $?
