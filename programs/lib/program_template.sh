#!/usr/bin/env sh
#
# Description:
#
# Shell program template.
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

NAME="$(basename $0)"

# USER CONFIGURATION

# DEBUG
is_dry_run=1
do_suppress_output=0
verbosity=0
test $is_dry_run -ne 0 && verbosity=99

# SOURCING FILES
. ./lib/utils.sh

# Prints information about the program and how to use it.
echo_help() {
	test
	printf 'Description

%s:
%s [Options]

Positional arguments must come before option flags.

%s:

%s:
-h/--help             -- Display this help message.
' "$(format_bold Usage)" "$NAME" "$(format_bold Positional arguments)" "$(format_bold Options)"
	exit 0
}

# Parses the arguments passed to the program.
parse_arguments() {
	arguments=$(getopt --name "$NAME" -o "h" -l "help" -- "$@")
	eval set -- "$arguments"
	while true; do
		case "$1" in
		-h | --help)
			echo_help
			exit 0
			;;
		--)
			shift
			break
			;;
		*)
			echo_error "parse_arguments" "Missing option flag. Try '$NAME --help' for more information"
			exit 1
			;;
		esac
	done
}

# Executes the program.
main() {
	test "$@" = "" && echo_error "main" "Missing required arguments.\n" && echo_help

	parse_arguments "$@"
	test $? -ne 0 && echo_error "main" "There was an error parsing the command line arguments. Exiting." && exit $?

	exit 0
}

main "$@"
exit $?
