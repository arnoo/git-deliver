#!/bin/bash

DELIVERY_PATH="$1"
source "$DELIVERY_PATH/yisti.conf"

function exit_if_error
	{
	[[ $? -eq 0 ]] || exit $1
	}

[[ -f "/tmp/delivery_vars.sh" ]] || exit 1
source "/tmp/delivery_vars.sh"

echo "    Setting new Lisp as active Varnish backend"

echo "Setting Varnish backend port to $NEW_PORT"
sed 's/port = "[0-9]\+"/port = "'$NEW_PORT'"/' "$DELIVERY_PATH/$NAME.vcl" > /tmp/$NAME.vcl
mv "$DELIVERY_PATH/$NAME.vcl"{,.bak}
cp /tmp/$NAME.vcl "$DELIVERY_PATH/$NAME.vcl"
exit_if_error 2

if (varnishadm -T localhost:6082 vcl.list | grep yisti2 | grep -q active); then
	NEWCONF="yisti"
	OLDCONF="yisti2"
else
	NEWCONF="yisti2"
	OLDCONF="yisti"
fi
varnishadm -T localhost:6082 vcl.discard $NEWCONF 2>&1 > /dev/null
echo -n "    "
varnishadm -T localhost:6082 vcl.load $NEWCONF /etc/varnish/yisti.vcl
exit_if_error 3
varnishadm -T localhost:6082 vcl.use $NEWCONF
exit_if_error 4
varnishadm -T localhost:6082 vcl.discard $OLDCONF 2>&1 > /dev/null
mv "$DELIVERY_PATH/$NAME".vcl{.bak,}

echo "    Purging cache"
varnishadm -T localhost:6082 ban obj.http.X-vhost == "'"$NAME"'"

if [[ $NB_SCREENS -gt 0 ]]; then
	echo -n "    Waiting for last connections to obsolete Lisp to close"
	while [[ `netstat --tcpip -pn 2>/dev/null | grep \:$OLD_PORT | grep \ $RUNNING_SERVER_PID\/ | wc -l` -gt 0 ]]; do
		echo -n "."
		sleep 2
	done
	echo ""
	echo "    No connections remaining, killing obsolete Lisp"
	kill $RUNNING_SCREEN_PID
fi

#rm /tmp/delivery_vars.sh

exit 0
