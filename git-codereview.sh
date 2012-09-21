#!/bin/bash

TEMP='/tmp/codereview'

CODEDIFF_PY="$HOME/bin/codediff.py"


CURRENT_DIR=`pwd`
REPO_ROOT=`git rev-parse --show-toplevel`
GIT_RESULT=$?

if [ "$GIT_RESULT" -gt 0 ]; then
  echo "Not a git repository!"
  exit 1
fi

chmod +x $CODEDIFF_PY

echo "========================="
echo "Current dir: $CURRENT_DIR"
echo "Repo root:   $REPO_ROOT"
echo "========================="



STAGED=`git diff --name-status -r --cached`

USED_DIFF="nothing"

if [ -z "$STAGED" ]; then
  echo "No staged files found. Using last commitdiff."
  COMMAND="git diff --name-status -r HEAD^ HEAD"
  USED_DIFF="commitdiff"
  # FILES=`git diff --name-status -r HEAD^ HEAD` # | awk '{ print $2 }'`
else
  echo "Using staged files."
  COMMAND="git diff --name-status -r --cached"
  USED_DIFF="staged"
  # FILES=`git diff --name-status -r --cached` # | awk '{ print $2 }'`
fi

echo "Changed files:"
#for i in `$COMMAND`; do
#  echo "LINE:__${i}__"
#  TYPE=`echo "$i"|awk '{ print $1 }'`
#  FILE=`echo "$i"|awk '{ print $2 }'`
#  echo "$TYPE: "
#  echo "$FILE"
#done

echo "Creating temp dirs for modified/added/deleted files..."
rm -rf $TEMP
#mkdir -pv "$TEMP/{OLD,NEW}"

# to simplify copying
cd "$REPO_ROOT"

$COMMAND | while read LINE
do    
  #echo "__${LINE}__"
  TYPE=`echo "${LINE}"|awk '{ print $1 }'`
  FILE=`echo "${LINE}"|awk '{ print $2 }'`
  #echo "$TYPE: $FILE"
  mkdir -p "$TEMP/OLD/`dirname $FILE`"
  mkdir -p "$TEMP/NEW/`dirname $FILE`"
  
  # copying OLD and NEW
  if [ "$USED_DIFF" == "staged" ]; then
    # OLD: HEAD   (git show HEAD:FILENAME)
    # NEW: STAGED (git show :FILENAME)
    # only if it isn't ADDED file
    [ "$TYPE" != "A" ] && git show HEAD:$FILE > "$TEMP/OLD/`dirname $FILE`/`basename $FILE`"
    # only if it isn't DELETED file
    [ "$TYPE" != "D" ] && git show     :$FILE > "$TEMP/NEW/`dirname $FILE`/`basename $FILE`"
  else
    if [ "$USED_DIFF" == "commitdiff" ]; then
    # OLD: HEAD^
    # NEW: HEAD
    # only if it isn't ADDED file
    [ "$TYPE" != "A" ] && git show HEAD^:$FILE > "$TEMP/OLD/`dirname $FILE`/`basename $FILE`"
    # only if it isn't DELETED file
    [ "$TYPE" != "D" ] && git show HEAD:$FILE > "$TEMP/NEW/`dirname $FILE`/`basename $FILE`"
    fi
  fi
  #echo ""
done

## do the diffing

python $CODEDIFF_PY "$TEMP/OLD" "$TEMP/NEW" -o "$TEMP/output"


## creating webserver config

DOCROOT="$TEMP/output"
PORT="4321"
PIDFILE="$TEMP/lighttpd.pid"
ERRORLOG="$TEMP/lighttpd.error.log"

## generate funny lighttpd config
cat << EOF > $TEMP/lighttpd.conf
server.document-root = "$DOCROOT"
server.port = $PORT
server.modules = ( "mod_setenv", "mod_cgi" )
#server.indexfiles = ( "gitweb.cgi" )
server.pid-file = "$PIDFILE"
server.errorlog = "$ERRORLOG"

cgi.assign = ( ".cgi" => "" )

mimetype.assign             = (
  ".pdf"          =>      "application/pdf",
  ".sig"          =>      "application/pgp-signature",
  ".spl"          =>      "application/futuresplash",
  ".class"        =>      "application/octet-stream",
  ".ps"           =>      "application/postscript",
  ".torrent"      =>      "application/x-bittorrent",
  ".dvi"          =>      "application/x-dvi",
  ".gz"           =>      "application/x-gzip",
  ".pac"          =>      "application/x-ns-proxy-autoconfig",
  ".swf"          =>      "application/x-shockwave-flash",
  ".tar.gz"       =>      "application/x-tgz",
  ".tgz"          =>      "application/x-tgz",
  ".tar"          =>      "application/x-tar",
  ".zip"          =>      "application/zip",
  ".mp3"          =>      "audio/mpeg",
  ".m3u"          =>      "audio/x-mpegurl",
  ".wma"          =>      "audio/x-ms-wma",
  ".wax"          =>      "audio/x-ms-wax",
  ".ogg"          =>      "application/ogg",
  ".wav"          =>      "audio/x-wav",
  ".gif"          =>      "image/gif",
  ".jpg"          =>      "image/jpeg",
  ".jpeg"         =>      "image/jpeg",
  ".png"          =>      "image/png",
  ".xbm"          =>      "image/x-xbitmap",
  ".xpm"          =>      "image/x-xpixmap",
  ".xwd"          =>      "image/x-xwindowdump",
  ".css"          =>      "text/css",
  ".html"         =>      "text/html",
  ".htm"          =>      "text/html",
  ".js"           =>      "text/javascript",
  ".asc"          =>      "text/plain",
  ".c"            =>      "text/plain",
  ".cpp"          =>      "text/plain",
  ".log"          =>      "text/plain",
  ".conf"         =>      "text/plain",
  ".text"         =>      "text/plain",
  ".txt"          =>      "text/plain",
  ".dtd"          =>      "text/xml",
  ".xml"          =>      "text/xml",
  ".mpeg"         =>      "video/mpeg",
  ".mpg"          =>      "video/mpeg",
  ".mov"          =>      "video/quicktime",
  ".qt"           =>      "video/quicktime",
  ".avi"          =>      "video/x-msvideo",
  ".asf"          =>      "video/x-ms-asf",
  ".asx"          =>      "video/x-ms-asf",
  ".wmv"          =>      "video/x-ms-wmv",
  ".bz2"          =>      "application/x-bzip",
  ".tbz"          =>      "application/x-bzip-compressed-tar",
  ".tar.bz2"      =>      "application/x-bzip-compressed-tar",
  ""              =>      "text/plain"
 )
EOF

PID=`ps aux |egrep "lighttpd.*$TEMP"|grep -v grep|awk '{ print $2 }'`

[ -n "$PID" ] && kill "$PID"

# start webserver
lighttpd -f $TEMP/lighttpd.conf > $TEMP/serveroutput &

# parse local ip
LOCALIP=`ifconfig eth0|egrep 'inet .* netmask .* broadcast'|awk '{ print $2 }'`

echo "LINK: http://$LOCALIP:$PORT/index.html"

cd "$CURRENT_DIR"

