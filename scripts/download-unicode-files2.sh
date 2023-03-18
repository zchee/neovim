#!/bin/sh

set -e
data_files=""
data_files_draft="CaseFolding.txt UnicodeData.txt EastAsianWidth.txt"
emoji_files="emoji-data.txt"

UNIDIR_DEFAULT='src/unicode'
DOWNLOAD_URL_BASE_DEFAULT='https://www.unicode.org/Public/15.1.0/ucd'
DOWNLOAD_URL_BASE_DRAFT='https://unicode.org/Public/draft/UCD/ucd'

# shellcheck disable=SC2268
if test "x$1" = 'x--help' ; then
  echo 'Usage:'
  echo "  $0[ TARGET_DIRECTORY[ URL_BASE]]"
  echo
  echo "Downloads files $data_files to TARGET_DIRECTORY."
  echo "Each file is downloaded from URL_BASE/\$filename."
  echo
  echo "Default target directory is $PWD/${UNIDIR_DEFAULT}."
  echo "Default URL base is ${DOWNLOAD_URL_BASE_DEFAULT}."
fi

UNIDIR=${1:-$UNIDIR_DEFAULT}
DOWNLOAD_URL_BASE=${2:-$DOWNLOAD_URL_BASE_DEFAULT}

for filename in $data_files ; do
  curl -sL -o "$UNIDIR/$filename" "$DOWNLOAD_URL_BASE/$filename"
done

for filename in $data_files_draft ; do
  curl -sL -o "$UNIDIR/${filename%%-*}" "$DOWNLOAD_URL_BASE_DRAFT/$filename"
done

for filename in $emoji_files ; do
  curl -sL -o "$UNIDIR/$filename" "$DOWNLOAD_URL_BASE_DEFAULT/emoji/$filename"
done
