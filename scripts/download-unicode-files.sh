#!/bin/sh

set -e
data_files="UnicodeData.txt CaseFolding.txt EastAsianWidth.txt"
emoji_files="emoji-data.txt"

UNIDIR_DEFAULT=unicode
DOWNLOAD_URL_BASE_DEFAULT='https://unicode.org/Public/UNIDATA'

if test x$1 = 'x--help' ; then
  echo 'Usage:'
  echo "  $0[ TARGET_DIRECTORY[ URL_BASE]]"
  echo
  echo "Downloads files $files to TARGET_DIRECTORY."
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

for filename in $emoji_files ; do
  curl -sL -o "$UNIDIR/$filename" "$DOWNLOAD_URL_BASE/emoji/$filename"
done
