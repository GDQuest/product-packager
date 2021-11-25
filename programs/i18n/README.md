# Translation tools

This directory contains the tools we use to streamline content translations at GDQuest.

We use them to create translation files for our courses, articles, and videos. They work for any language.

## File format and workflow

We use the gnu gettext format to manage translations. It allows us to track individual translation strings that changed and update them efficiently.

Combined with the translation app [poedit](https://poedit.net/), we get translation memory: the app keeps a database of all previous translations and automatically finds partial and exact matches in new documents.

To start translating a lesson to another language:

1. We generate the `.pot` and `.po` (gettext) files for that language from the source markdown document.
2. The translator translates each string in the `.po` file and sends the translations back.
3. We convert the `.po` file into a new markdown document.

If the `.po` file already exists for that lesson and the lesson changed, the program updates sentences that changed in the existing `.po` file.

## What the `i18n` program does

We use the free software `po4a` to generate translation files.

The `i18n` program in this directory allows you to:

1. Generate a new repository from an existing one with all content files and Godot projects to translate.
2. Generate a `po4a` configuration file, which helps automate updating translation files when the content changes.

With `po4a`, you can:

1. Generate new `.po` files from markdown files or detect existing `.po` files and update their content.
2. Extract comments from gdscript code files and create and maintain a `.po` file for each of them.
3. Generate a copy of the course in another language from complete or near-complete `.po` files.

### `i18n` usage instructions

These instructions are only for Linux.

Pre-requisites:

1. Install `po4a`.
   - On Ubuntu Linux, you can run `sudo apt install po4a`.
   - It should be available from your package manager with most distributions.
   - If not, you need to grab the Perl source code from the [latest GitHub release](https://github.com/mquinson/po4a/releases) and expose the program to your `PATH` environment variable yourself.
2. Add the `export PERL5LIB=path/to/perl5:$PERL5LIB` line to your `$HOME/.profile` file and logout-login to take effect.
   - The `perl5` directory in question is the one next to this README file.
   - For example, on my computer, I wrote `export PERL5LIB=/home/nathan/Repos/product-packager/programs/i18n/perl5:$PERL5LIB`.
3. The `i18n` program requires you to have Python 3 installed to work. You need to install some requirements too with `pip3 install -r requirements.txt`.

How to use:

1. Run `./i18n path/to/repository`. This creates a copy of the repository in a new folder with an `-es` next to the given path.
2. Move into the newly generated folder. It'll be living next to the original repository.
3. In that new folder, run `po4a po4a.conf`. This will create a catalog of all your translation strings and generate markdown and GDScript files in the target language if you have enough translations.
   - You can run `po4a --keep=0 po4a.conf` to generate `*.md` and `*.gd` files even if they're untranslated.
   - For more information, refer to the `po4a` documentation by running `man po4a`.

The generated translation files (`*.po` and `*.pot`) end up in a folder named `i18n/` in the generated repository.
