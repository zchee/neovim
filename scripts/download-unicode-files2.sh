#!/bin/sh

set -e
data_files=""
data_files_15_0_0="CaseFolding-15.0.0d1.txt UnicodeData-15.0.0d6.txt EastAsianWidth-15.0.0d5.txt"
emoji_files="emoji-data.txt"

UNIDIR_DEFAULT=src/unicode
DOWNLOAD_URL_BASE_DEFAULT='https://unicode.org/Public/UNIDATA'
DOWNLOAD_URL_BASE_15_0_0='https://unicode.org/Public/15.0.0/ucd'

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

for filename in $data_files_15_0_0 ; do
  curl -sL -o "$UNIDIR/${filename%%-*}.txt" "$DOWNLOAD_URL_BASE_15_0_0/$filename"
done

for filename in $emoji_files ; do
  curl -sL -o "$UNIDIR/$filename" "$DOWNLOAD_URL_BASE_15_0_0/emoji/$filename"
done
