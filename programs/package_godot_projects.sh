#!/usr/bin/env sh

dir_godot="godot"

package_godot_projects() {
	directory_godot="$dir_content"/"$dir_godot"
	test -d "$directory_godot" || exit 1

	directory_start=$(pwd)
	directory_export="$directory_godot"/export

	if test "$is_dry_run" -eq 0; then
		cd "$directory_godot" || exit 1
		test -d "$dir_dist" || mkdir "$dir_dist"
		test -d "$directory_export" || mkdir "$directory_export"
	fi

	echo_message "Copying Godot projects to a temporary directory..."
	to_copy=$(find . -mindepth 1 -maxdepth 1 -not -path "./tutorial" -not -path "./dist" -type d)
	if ! test "$is_dry_run" -eq 0; then
		for i in $to_copy; do
			cp -r "$i" dist
		done
	fi
	echo_message "Done."

	if test "$is_dry_run" -eq 0; then
		echo_message "Removing .import directories..."
		rm -rf "$(find . -path dist -type d -name .import)"
		echo_message "Done."

		archive_name=$(strings_to_filename "$PROJECT_TITLE")".zip"
		zip -r "$archive_name" dist/*
		mv -v --backup --force "$archive_name" "$dir_dist"

		echo_message "Removing the $directory_export directory..."
		rm -rf "$directory_export"
		echo_message "Done."

		cd "$directory_start" || exit 1
	fi

}

