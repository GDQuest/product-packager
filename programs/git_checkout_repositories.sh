# Tries to reset git repositories to the master branch.
# Prints information about the process, and the list of repositories the function could not
# checkout.
#
# Arguments:
# $@ - a list of paths to git repositories. They can end up with the `.git` folder, the function
# will automatically normalize the paths.
#
# Flags:
# -s/--short - Only output the list of repositories that could not be checked out.
git_try_checkout_to_master() {
	start_dir=$(pwd)
	is_short_form=0
	case $1 in
	-s | --short)
		is_short_form=1
		shift
		;;
	esac

	# Filter and normalize git dirpaths
	git_directories=$(mktemp)
	for i in "$@"; do
		dir=$(echo "$i" | sed 's/\/\.git.*$//')
		cd "$dir" || continue
		git status >/dev/null || continue
		echo "$dir" >>git_directories
	done

	file_errors=$(mktemp)
	for i in $(cat "$git_directories"); do
		cd "$i" || continue

		status_output=$(git status --porcelain)

		test "$is_short_form" -eq 0 && test "$status_output" = "" || echo_message "The repository $i is dirty."

		output=$(git checkout master)
		test "$is_short_form" -eq 0 && echo "$output"
		if test $? -gt 0; then
			echo "$i" >>file_errors
		fi
	done

	test "$is_short_form" -eq 0 && printf "\nCouldn't checkout to master in the following repositories:\n"
	cat "$file_errors"
	cd "$start_dir" || exit 1
}
