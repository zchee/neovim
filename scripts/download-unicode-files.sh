#!/bin/sh

set -ex
# data_files="UnicodeData.txt CaseFolding.txt"
data_files="CaseFolding.txt"
# data_files_14_0_0="EastAsianWidth-14.0.0d5.txt"
data_files_14_0_0="UnicodeData-14.0.0d7.txt EastAsianWidth-14.0.0d5.txt"
emoji_files="emoji-data.txt"

UNIDIR_DEFAULT=unicode
DOWNLOAD_URL_BASE_DEFAULT='https://unicode.org/Public/UNIDATA'
DOWNLOAD_URL_BASE_14_0_0='https://unicode.org/Public/14.0.0/ucd'

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

for filename in $data_files_14_0_0 ; do
  curl -sL -o "$UNIDIR/${filename%%-*}.txt" "$DOWNLOAD_URL_BASE_14_0_0/$filename"
done

for filename in $emoji_files ; do
  curl -sL -o "$UNIDIR/$filename" "$DOWNLOAD_URL_BASE/emoji/$filename"
done
