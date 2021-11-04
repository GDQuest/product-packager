# Translation tools

/!\ This directory and Python scripts are a work in progress.

A set of programs to translate courses from English to other languages.

## Workflow

We use the GNU gettext format to manage translations. It allows us to track individual translation strings that changed and update them efficiently.

Combined with the translation app [poedit](https://poedit.net/), we get translation memory: the app keeps a database of all previous translations and automatically finds partial and exact matches in new documents.

To start translating a lesson to another language, we:

1. Generate the .po (gettext) file for that language from the source markdown document.
2. The translator translates each string in the .po file and sends the translations back.
3. We convert the .po file into a new markdown document.

If the .po file already exists for that lesson and the lesson changed, we can update the .po file instead, replacing sentences that changed.

## Requirements

Those are temporary tech. requirements to develop the tools needed to translate courses.

We need tools to help streamline the above workflow and create copies of course repositories in languages other than English.

The programs in this directory should allow us to:

1. Generate new .po files from markdown files or detect existing .po files and update their content.
2. Extract comments from GDScript code files and create and maintain a .po file for all of them (there aren't so many code comments. We need to split them into different .po files).
3. Generate a copy of the course in another language from complete or near-complete .po files.
4. The new copy of the course (say, in Spanish) should build with `scons` like the original.

### General technical requirements

The programs should be in Python and rely on the `po4a` suite of translation tools to save time. The `po4a` programs can generate .po files from markdown, update existing translations, and convert .po files into new, translated markdown documents.

Note: A base program called `po4a` automates these steps using some configuration file, but it seems designed more for software. The format and options are a bit limiting and for example wouldn't support Godot, so I couldn't make it work with our projects.

There are individual programs you can call from scripts, however, that give you much more flexibility:

- po4a-gettextize generates a fresh .po file from an input text document.
- po4a-updatepo updates an existing .po file using its source text document.
- po4a-translate outputs a translated text document from the source and the .po file.

#### Python requirements

Use the `datargs` module to parse command-line arguments like other programs in this repo. It makes the command-line interface typed and easy to update.

``` python
from dataclasses import dataclass
from datargs import arg, parse


@dataclass
class Args:
    project_path: Path = arg(positional=True, help="Path to the project's repository.")
    language_code: str = arg(
        default=DEFAULT_LANGUAGE_CODE, help="Language code for the translation files."
    )
    content_dirname: str = arg(
        default=DEFAULT_CONTENT_DIRNAME,
        help="Name of the directory containing markdown files.",
    )


def main():
    args = parse(Args)
```

Also, please use long option names when calling po4a cli programs from Python (e.g. use `--format` rather than `-f` in your Python code).

### Generating and updating .po files from markdown

The `generate_translation_files.py` program already generates new .po files from a list of markdown files. Currently, it doesn't detect and update existing files. Given markdown files with matching .po files, it should call `po4a-updatepo` to update the .po files.

### Extracting GDScript comments as translation strings

This is the hardest part of the job.

As we use comments a lot when teaching, we need to extract comments and docstrings from Godot projects to translate them to other languages.

This program or collection of programs should:

1. Find all relevant comments to translate in a Godot project.
2. Unwrap wrapped lines into a single translation string.
   - We wrap comments at 80 characters in our code, splitting sentences over multiple lines. We need to turn them back into a continuous sentence for the translators.
3. Generate or update an existing .po file from collected comments. Gettext is a stable text format so we can do that ourselves.
4. Given the .po file, we should be able to output a copy of the whole Godot project with the GDScript code preserved but the comments translated to Spanish, with comments wrapping at 80 characters.

Steps 3 and 4 involve keeping track of the line numbers and context of the comments. You can find an example of how to generate the .po file from Godot's translation extraction script: https://github.com/godotengine/godot/blob/master/doc/translations/extract.py (see the HEADER constant and `_generate_translation_catalog_file()` for the .po format).

### Creating a copy of the repository in another language

Using the programs above, we should be able to generate a copy of the repository in the target language, ready to build using `scons`.

The translated repository should not include untranslated lessons/guides. However, it should always include the Godot project(s) with all GDScript files, whether code comment translations are complete or not.

You can use `po4a-translate` to automatically detect if a .po file has enough translations completed to output a translated document with the `--keep` option.

---

### `i18n` instructions

1. Add `export PERL5LIB=path_to_perl5_repo_folder:$PERL5LIB` to your `$HOME/.profile` and logout-login to take effect.
2. Run `i18n path_to_gdquest_godot_repo` prepared with guides. This creates a new folder with an `-es` suffix along side the given path.
3. Move into the new folder with `cd path_to_gdquest_godot_repo-es`.
4. Run `po4a po4a.conf`. You can run `po4a --keep=0 po4a.conf` to generate `*.md` and `*.gd` files even if they're untranslated.
5. Profit!

The translation files (`*.po` and `*.pot`) get generated in `path_to_gdquest_godot_repo-es/i18n`.
