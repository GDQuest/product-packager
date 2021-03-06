#!/usr/bin/env sh

# CONSTANTS
VERBOSITY_INFO=1
VERBOSITY_WARNING=2
VERBOSITY_DEBUG=3

# Terminal formatting, for pretty printing
FORMAT_NORMAL=$(tput sgr0)
FORMAT_BOLD=$(tput bold)
FORMAT_ITALIC=$(tput sitm)
FORMAT_UNDERLINE=$(tput smul)
FORMAT_BLINK=$(tput blink)

COLOR_BLACK=$(tput setaf 1)
COLOR_RED=$(tput setaf 1)
COLOR_GREEN=$(tput setaf 2)
COLOR_YELLOW=$(tput setaf 3)
COLOR_BLUE=$(tput setaf 4)
COLOR_MAGENTA=$(tput setaf 5)
COLOR_CYAN=$(tput setaf 6)
COLOR_WHITE=$(tput setaf 7)

# Prints a message only if the $verbosity level is high enough.
# $verbosity must be defined in the importing program.
#
# Arguments:
# $1 - verbosity level of the message
echo_debug() {
	test "$verbosity" -ge "$1" || exit

	case "$1" in
	$VERBOSITY_INFO) prefix="INFO:" ;;
	$VERBOSITY_WARNING) prefix="WARNING:" ;;
	$VERBOSITY_DEBUG) prefix="DEBUG:" ;;
	*) exit ;;
	esac
	shift
	echo $prefix "$@"
}

echo_error() {
	test "$do_suppress_output" -eq 0 || exit
	function_name=$1
	shift
	printf "%s in %s: %s" "$(color_apply red Error)" "$(format_bold "$function_name")" "$*"
}

# Outputs a message only if $do_suppress_output is falsy
echo_message() {
	test $do_suppress_output -eq 0 && echo "$*"
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

# Apply the format to the text and
format_apply() {
	case $1 in
	b | bold) fmt=$FORMAT_BOLD ;;
	i | italic) fmt=$FORMAT_ITALIC ;;
	u | underline) fmt=$FORMAT_UNDERLINE ;;
	k | blink) fmt=$FORMAT_BLINK ;;
	*) fmt=$FORMAT_NORMAL ;;
	esac
	printf "%s%s%s" "$fmt" "$*" "$FORMAT_NORMAL"
}

# Prints the text with inserted format codes for the current terminal.
# Resets to the normal format at the end of the text
#
# Arguments:
# $1 - A string representing the format, e.g. b or bold. See valid formats below.
# $* - The text to format.
format_apply() {
	case $1 in
	b | bold) fmt=$FORMAT_BOLD ;;
	i | italic) fmt=$FORMAT_ITALIC ;;
	u | underline) fmt=$FORMAT_UNDERLINE ;;
	k | blink) fmt=$FORMAT_BLINK ;;
	*) fmt=$FORMAT_NORMAL ;;
	esac
	shift
	printf "%s%s%s" "$fmt" "$*" "$FORMAT_NORMAL"
}

format_bold() {
	printf "%s%s%s" "$FORMAT_BOLD" "$*" "$FORMAT_NORMAL"
}

format_italic() {
	printf "%s%s%s" "$FORMAT_ITALIC" "$*" "$FORMAT_NORMAL"
}

format_underline() {
	printf "%s%s%s" "$FORMAT_UNDERLINE" "$*" "$FORMAT_NORMAL"
}

# Prints the text with inserted color codes for the current terminal.
# Resets to the normal format at the end of the text
#
# Arguments:
# $1 - a string representing the color, e.g. b or bold. See valid colors below.
# $* - The text to format.
color_apply() {
	case $1 in
	k | black) col=$COLOR_BLACK ;;
	r | red) col=$COLOR_RED ;;
	g | green) col=$COLOR_GREEN ;;
	y | yellow) col=$COLOR_YELLOW ;;
	b | blue) col=$COLOR_BLUE ;;
	m | magenta) col=$COLOR_MAGENTA ;;
	c | cyan) col=$COLOR_CYAN ;;
	w | white) col=$COLOR_WHITE ;;
	*) col=$FORMAT_NORMAL ;;
	esac
	shift
	printf "%s%s%s" "$col" "$*" "$FORMAT_NORMAL"
}
