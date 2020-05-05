videos_render_with_bpsrender() {
	bpsrender --help >/dev/null
	test $? -ne 0 && echo "There was an error running 'bpsrender'.
The program 'bpsrender' must be available on the system PATH variable for this program to work.
For more information, see https://en.wikipedia.org/wiki/PATH_(variable).
Cancelling video rendering." && exit 1

	blend_files=$(find "$dir_content" -mindepth 1 -maxdepth 3 -type f -iname "*.blend")

	count=$(printf "%s\n" "${blend_files}" | wc -l)
	echo_message "\nRendering $count video projects with 'bpsrender'\n"

	content_path_length=$(echo "$dir_content" | wc --chars)
	for blend_file in $blend_files; do
		chapter_directory=$(echo "$blend_file" | cut --characters "$content_path_length"-)
		echo_debug 1 "Rendering file $blend_file"
		test "$is_dry_run" -eq 0 && bpsrender --output "$chapter_directory" -- "$blend_file"
	done
}

