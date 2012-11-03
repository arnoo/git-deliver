YISDIR=/files/yisti

if [[ ! -d log ]]; then
	echo "ERROR : log directory not found... if you continue, it will be created."
	confirm_or_exit
	mkdir log
fi

if [[ ! -f `which lessc 2> /dev/null` ]]; then
	echo "ERROR : lessc not found."
	confirm_or_exit
fi

if [[ ! -f `which java 2> /dev/null` ]]; then
	echo "ERROR : uglifyjs not found."
	confirm_or_exit
fi

if [[ ! -f `which java 2> /dev/null` ]]; then
	echo "ERROR : java not found (for CSS minification)."
	confirm_or_exit
fi

if [[ `ps -C varnishd | wc -l` == 1 ]]; then
	echo "ERROR : Varnish is not running"
	exit
fi

SCREENS=`screen -ls | grep \\\-$NAME`
NB_SCREENS=`screen -ls | grep -c \\\-$NAME`
if [[ $NB_SCREENS -gt 1 ]]; then
	echo "More than one ($NB_SCREENS) screens found... you're on your own."
	screen -ls
	exit
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

if [[ $NB_SCREENS -gt 0 ]]; then
	if [[ $NEW_GIT == $RUNNING_GIT ]]; then
		echo "It looks like this version is already delivered and running."
		confirm_or_exit
	fi

	DIFF_LINES=`git diff $RUNNING_GIT $NEW_GIT | wc -l`
	if [[ $NEW_GIT != $RUNNING_GIT ]]; then
		if [[ $DIFF_LINES == "0" ]]; then
			echo "No difference between running version and this one (empty diff)"
			confirm_or_exit
		fi

		if [[ $NEW_GIT != $RUNNING_GIT ]] && [[ $LISP_DIFF_LINES == "0" ]] && [[ $DIFF_LINES -gt 0 ]]; then
			echo "No Lisp changes, and it looks like this version is already delivered and running."
			if [[ ! $DEVP ]]; then
				read -p "Just push static files ? (y/n) " -n 1
				if [[ $REPLY =~ ^[Yy]$ ]]; then
					echo "Pushing static files to CDN"
					./pushstatic.sh
					exit 0
				fi
			else
				confirm_or_exit
			fi
		fi
	fi
fi

DB_DIFF=`git diff $RUNNING_GIT $NEW_GIT $DB_FILES`
LISP_DIFF_LINES=`git diff $RUNNING_GIT $NEW_GIT *.lisp | wc -l`
if [[ `echo "$DB_DIFF" | wc -l` != "1" ]]; then
echo "Warning : there are database changes."
echo "$DB_DIFF"
echo "You'll have to apply them manually, either now or when the new Lisp is ready"
read -p "Press any key to continue"
fi

echo ""


echo -n "Starting new Lisp"
NEW_SCREEN_PID=`$YISDIR/start.sh | awk -F\. '/[0-9]\./ {print $1}'`
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
	NEW_SCREEN_PID=`$YISDIR/start.sh | awk -F\. '/[0-9]\./ {print $1}'`
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
	confirm_or_exit
fi

echo "New Lisp is online"
