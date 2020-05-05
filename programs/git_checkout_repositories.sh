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
# Filters and tries to checkout git repositories to master. Prints information about repositories
# that couldn't be switched to the master branch.

set -euo pipefail

NAME="$(basename $0)"

# Debug tools
FORMAT_NORMAL=$(tput sgr0)
FORMAT_BOLD=$(tput bold)

format_bold() {
	printf "%s%s%s" "$FORMAT_BOLD" "$*" "$FORMAT_NORMAL"
}

echo_help() {
	printf 'Filters and tries to checkout git repositories to master. Prints information about repositories
that could not be switched to the master branch.

%s:
'"$NAME"' [Options] -- $directory_1 $directory_2 ...

%s:
$directory_1 ... -- List of paths to git repositories. The script tests and filters valid git
repositories so you can use a wildcard, for instance.

%s:
-h/--help		 -- Display this help message.
-d/--dry-run	 -- Run without building any files and output debug information.
-s/--short       -- Only output the list of repositories that could not be switched.
' "$(format_bold Usage)" "$(format_bold Positional arguments)" "$(format_bold Options)"
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
		--short) args+=(-s) ;;
		*) args+=("$arg") ;;
		esac
	done

	set -- "${args[@]}"
	while getopts "h,d,s" OPTION; do
		case $OPTION in
		h)
			echo_help
			break
			;;
		d)
			is_dry_run=1
			;;
		s)
			use_short_output=1
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

# Tries to reset git repositories to the master branch.
# Prints information about the process, and the list of repositories the function could not
# checkout.
#
# Arguments:
# $@ - a list of paths to git repositories. They can end with the `.git` folder, the function
# will automatically normalize the paths.
git_try_checkout_to_master() {
	start_dir=$(pwd)

	# Filter and normalize git dirpaths
	git_directories=$(mktemp)
	sed -i 's/\/\.git.*$//' $temp_file
	while read line; do
		cd "$line" || continue
		git status >/dev/null || continue
		echo "$line" >>git_directories
	done <$temp_file

	file_errors=$(mktemp)
	while read line; do
		cd "$line" || continue

		status_output=$(git status --porcelain)

		test "$use_short_output" -eq 0 -a "$status_output" != "" || echo "The repository $line is dirty:\n$status_output"

		output=$(git checkout master)
		test "$use_short_output" -eq 0 && echo "$output"
		if test $? -gt 0; then
			echo "$line" >>$file_errors
		fi
	done <$git_directories

	test $use_short_output -eq 0 && printf "\nCouldn't checkout to master in the following repositories:\n"
	cat $file_errors
	cd "$start_dir" || exit 1
}

main() {
	local is_dry_run=0
	local temp_file=$(mktemp)

	local use_short_output=0
	filepaths=$(parse_cli_arguments "$@")
	compress_videos $temp_file
	rm $temp_file
}

main "$@"
exit $?
