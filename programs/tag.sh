#!/usr/bin/env sh
# vim:let g:is_bash=1:set filetype=sh:

Color_Off='\033[0m'
Red='\033[0;31m'
Yellow='\033[0;33m'
Green='\033[0;32m'
Blue='\033[0;34m'
ScriptName="$0"


help(){
  if [ "$1" == "help" ]; then
    echo "Shows a short and helpful help text"
    exit 0
  fi
  echo ""
  echo "Version helper"
  echo ""
  echo "please use one of the following commands:"
  for i in ${!funcs[@]}; do
    command=${funcs[i]}
    if [[ ! $command == *_help ]]; then
      echo -e "  - $Yellow${command//_/:}$Color_Off"
    fi
  done
  echo ""
  echo "you can get more info about commands by writing "
  echo -e "$Yellow$ScriptName <command>:help$Color_Off"
  echo "you dry run most (but not all) commands by setting the \$DRY env variable"
  echo ""
  echo "Example usages:"
  echo ""
  echo -e "- run \`$Yellow$ScriptName create$Color_Off\` in a commit hook to make sure you"
  echo    "  create a new tag when you bump the version in product_packager.nimble"
  echo -e "- run \`$Yellow$ScriptName verify$Color_Off\` in a build script to make sure you"
  echo    "  build a version that matches the file version"
  echo -e "- run \`$Yellow$ScriptName verify:upstream$Color_Off\` to make sure the tags have"
  echo    "  been uploaded"
  
}


LATEST_TAG=$(git describe --tags --abbrev=0 --match "v*.*.*")
LATEST_TAG="${LATEST_TAG:1}"
VERSION=$(awk -F "=" '/^version/ {gsub(/[ \t"]/, "", $2); print $2}' product_packager.nimble)


function verify_help(){
  echo "Verifies the latest git tag and the current version match"
  echo ""
  echo "Syntax:"
  echo -e "  ${Blue}$ScriptName verify [noerror]$Color_Off"
  echo ""
  echo "Options:"
  echo -e " - ${Yellow}noerror$Color_Off: (optional) exits with an error code"
  echo ""
}


function verify(){
  do_exit=0
  if [ "$1" = "noerror" ]; then
    do_exit=1
  fi 
  if [ ! "$LATEST_TAG" = "$VERSION" ]; then
    if [ -z "$LATEST_TAG" ]; then
      echo -e >&2 "${Red}ERROR: Explicit version $VERSION is set, but no version git tag was found$Color_Off"
    else
      echo -e >&2 "${Red}ERROR: the version git tag $LATEST_TAG is different from the explicit version $VERSION$Color_Off"
    fi
    if [ $do_exit -eq 0 ]; then
      exit 1
    fi
    return 1
  fi
  command="git diff -s --exit-code product_packager.nimble"
  _run "$command"
  response="$?"
  if [ $response -ne 0 ]; then
    echo -e >&2 "${Red}ERROR: the file \`product_packager.nimble\` has been modified$Color_Off"
    if [ $do_exit -eq 0 ]; then
      exit 1
    fi
  fi
  if [ $do_exit -eq 0 ]; then
    exit 0
  fi
  echo "the version git tag $LATEST_TAG matches the explicit version $VERSION"
  return 0
}


function verify_upstream_help(){
  echo "Checks that upstream has the same last tag as local"
  echo "Syntax:"
  echo -e "  ${Blue}$ScriptName verify:upstream$Color_Off"
  echo ""
}


function verify_upstream(){
  if [ -z "$LATEST_TAG" ]; then
    echo -e >&2 "${Red}ERROR: no version git tag was found$Color_Off"
    exit 1
  fi
  command="git ls-remote --exit-code origin refs/tags/v$LATEST_TAG"
  _run "$command"
  response="$?"
  if [ $response -ne 0 ]; then
    echo -e >&2 "${Red}ERROR: version git tag $LATEST_TAG was not found on origin"
    echo -e >&2 "make sure you use \`${Yellow}git push --tags\`$Color_Off!"
    exit 1
  fi
  exit 0
}


function create_help(){
  echo "Creates a matching tag for the latest version found in the nimble file"
  echo ""
  echo "Syntax:"
  echo -e "  ${Blue}$ScriptName create [noconfirm]$Color_Off"
  echo ""
  echo "Options:"
  echo -e " - ${Yellow}noconfirm$Color_Off: (optional) creates the tag if necessary"
  echo ""
}


function create(){
  do_confirm=0
  if [ "$1" = "noconfirm" ]; then
    do_confirm=1
  fi 
  if ! verify noerror; then
    if [ $do_confirm -eq 0 ]; then
      read -p "Do you want to create the tag? " -n 1 -r
      echo ""
      if [[ ! $REPLY =~ ^[Yy]$ ]]
      then
        echo "Exiting"
        exit 0
      fi
    fi
    echo "Will set the tag"
    command="git tag v$VERSION"
    _run "$command"
    echo -e "Tag created, do not forget to push to remote with \n${Yellow}git push --tags$Color_Off"
  fi
}


function localhooks_help(){
  echo "sets your project git hooks to the correct directory \`programs/hooks\`"
}


function localhooks(){
  command="git config core.hooksPath programs/hooks"
  _run "$command"
}

###############################################################################
# UTILITIES
###############################################################################

# Runs a provided command. In dry mode, only prints it
_run(){
  echo -e "${Yellow}$1${Color_Off}"
  if [[ ! $DRY ]]; then
    eval $1
  fi
}

###############################################################################
# BOOSTRAP
###############################################################################

# Starts the script
function _bootstrap(){
  funcs=(`declare -F | awk '{print $NF}' | sort | egrep -v "^_"`)
  command=${1//:/_}

  if [[ $DRY ]]; then
    echo -e "${Yellow}---"
    echo "DRY is set, will run dry (no changes will be made)"
    echo -e "---$Color_Off"
  fi

  if [[ " ${funcs[*]} " =~ " ${command} " ]]; then
    shift
    $command $@
    exit 0
  else
    if [[ $command ]]; then
      echo ""
      echo "\`${command}\` isn't a recognized command"
      echo ""
    fi
    help
    exit 1
  fi
}

_bootstrap $@