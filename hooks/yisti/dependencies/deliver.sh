#!/bin/bash

cd "$1"
DELIVERY_PATH="$1"
source "$DELIVERY_PATH/yisti.conf"

if [[ ! -f `which lessc 2> /dev/null` ]]; then
	echo "ERROR : lessc not found."
	exit 1
fi

if [[ ! -f `which java 2> /dev/null` ]]; then
	echo "ERROR : uglifyjs not found."
	exit 2
fi

if [[ ! -f `which java 2> /dev/null` ]]; then
	echo "ERROR : java not found (for CSS minification)."
	exit 3
fi

if [[ `ps -C varnishd | wc -l` == 1 ]]; then
	echo "ERROR : Varnish is not running"
	exit 4
fi

if [[ ! -f $NAME.vcl ]]; then
	echo "$NAME.vcl not found"
	exit 5
fi

if [[ ! -f ../yisti/start.sh ]]; then
	echo "../yisti/start.sh not found"
	exit 6
fi


mkdir log

SCREENS=`screen -ls | grep \\\-$NAME`
NB_SCREENS=`screen -ls | grep -c \\\-$NAME`
if [[ $NB_SCREENS -gt 1 ]]; then
	echo "More than one ($NB_SCREENS) screens found... you're on your own."
	screen -ls
	exit 6
fi
if [[ $NB_SCREENS -gt 0 ]]; then
	RUNNING_SCREEN_PID=`echo "$SCREENS" | awk -F\.  '{sub(/^\s+/,"",$1); print $1}'`
	RUNNING_SERVER_PID=$RUNNING_SCREEN_PID
	while [[ $PNAME != 'sbcl' ]]; do
		INFO=`ps --ppid $RUNNING_SERVER_PID | tail -n +2`
		PNAME=`echo "$INFO" | awk '{sub(/CMD /,"",$4); print $4}'`
		RUNNING_SERVER_PID=`echo "$INFO" | awk '{print $1}'`
	done
	NETCOMMAND="netstat -apn 2>/dev/null | awk '/$RUNNING_SERVER_PID\// && /LISTEN/ {sub(/^.*:/,\"\",\$4); print \$4}'"
	OLD_PORT=`echo "$NETCOMMAND" | bash`
	echo "Found running server (Screen PID : $RUNNING_SCREEN_PID, Server PID : $RUNNING_SERVER_PID, port $OLD_PORT)"
else
	echo "No running server found"
fi

echo ""

echo -n "Starting new Lisp"
NEW_SCREEN_PID=`../yisti/start.sh | awk -F\. '/[0-9]\./ {print $1}'`
echo -n " (screen : $NAME.$NEW_SCREEN_PID) "

NEW_SCREEN_LOG="log/screen_$NEW_SCREEN_PID"
truncate -s 0 $NEW_SCREEN_LOG
screen -rd $NEW_SCREEN_PID -p 0 -X log off
screen -rd $NEW_SCREEN_PID -p 0 -X logfile $NEW_SCREEN_LOG
screen -rd $NEW_SCREEN_PID -p 0 -X log on
STARTING=true
while $STARTING; do
sleep 2
if (grep "\"Server ready\"" $NEW_SCREEN_LOG > /dev/null); then
	echo "done"
	STARTING=false
elif (grep -q "ENOMEM" $NEW_SCREEN_LOG) || (grep -q "Heap exhausted" $NEW_SCREEN_LOG); then
	echo ""
	echo -n "Memory error, restarting compilation"
	kill $NEW_SCREEN_PID
	NEW_SCREEN_PID=`../yisti/start.sh | awk -F\. '/[0-9]\./ {print $1}'`
	NEW_SCREEN_LOG="log/screen_$NEW_SCREEN_PID"
	truncate -s 0 $NEW_SCREEN_LOG
	screen -rd $NEW_SCREEN_PID -p 0 -X log off
	screen -rd $NEW_SCREEN_PID -p 0 -X logfile $NEW_SCREEN_LOG
	screen -rd $NEW_SCREEN_PID -p 0 -X log on
else
	echo -n "."
fi
done

NEW_SERVER_PID=$NEW_SCREEN_PID
PNAME=""
while [[ $PNAME != 'sbcl' ]]; do
INFO=`ps --ppid $NEW_SERVER_PID | tail -n +2`
PNAME=`echo "$INFO" | awk '{print $4}'`
	NEW_SERVER_PID=`echo "$INFO" | awk '{print $1}'`
done

echo "New Lisp started (Screen PID : $NEW_SCREEN_PID, Server PID : $NEW_SERVER_PID)"
echo ""

NETCOMMAND="netstat -apn 2>/dev/null | awk '/$NEW_SERVER_PID\// && /LISTEN/ {sub(/^.*:/,\"\",\$4); print \$4}'"
NEW_PORT=`echo "$NETCOMMAND" | bash`

echo "Checking HTTP access to new Lisp on port $NEW_PORT"
wget -q http://localhost:$NEW_PORT
if [[ $? != 0 ]]; then
	echo "ERROR : Could not do HTTP request to new Lisp on port $NEW_PORT"
	exit 7
fi

echo "New Lisp is online"
echo "NEW_PORT=\"$NEW_PORT\" \
      OLD_PORT=\"$OLD_PORT\" \
      NAME=\"$NAME\" \
      NB_SCREENS=\"$NB_SCREENS\" \
      RUNNING_SERVER_PID=\"$RUNNING_SERVER_PID\" \
      RUNNING_SCREEN_PID=\"$RUNNING_SCREEN_PID\"" > /tmp/delivery_vars.sh
