#!/usr/bin env sh
GODOT_BASE_PATH=mdx-utils
GODOT_PATH=src/md/godot
git remote add -f -t master --no-tags godot https://github.com/godotengine/godot.git 2> /dev/null
[ -d $GODOT_PATH ] && git rm -rf $GODOT_PATH
git read-tree --prefix=$GODOT_BASE_PATH/$GODOT_PATH/doc/classes -u godot/master:doc/classes
git read-tree --prefix=$GODOT_BASE_PATH/$GODOT_PATH/editor/icons -u godot/master:editor/icons
git read-tree --prefix=$GODOT_BASE_PATH/$GODOT_PATH/modules -u godot/master:modules
