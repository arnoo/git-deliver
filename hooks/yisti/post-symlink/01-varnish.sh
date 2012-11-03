echo "Setting new Lisp as active Varnish backend"

sed "s/port [0-9]+$/port $YISTI_NEW_PORT/" $YISTI_NAME.vcl > /tmp/$YISTI_NAME.vcl
mv $YISTI_NAME.vcl{,.bak}
cp /tmp/$YISTI_NAME.vcl $YISTI_NAME.vcl

if (varnishadm -T localhost:6082 vcl.list | grep yisti2 | grep -q active); then
	YISTI_NEWCONF="yisti"
	YISTI_OLDCONF="yisti2"
else
	YISTI_NEWCONF="yisti2"
	YISTI_OLDCONF="yisti"
fi
varnishadm -T localhost:6082 vcl.load $YISTI_NEWCONF /etc/varnish/yisti.vcl
varnishadm -T localhost:6082 vcl.use $YISTI_NEWCONF
varnishadm -T localhost:6082 vcl.discard $YISTI_OLDCONF
mv $YISTI_NAME.vcl{.bak,}

echo "Purging cache"
varnishadm -T localhost:6082 ban obj.http.X-vhost == '$NAME'
#TODO: reinit cache ?

if [[ $YISTI_NB_SCREENS -gt 0 ]]; then
	echo -n "Waiting for last connections to obsolete Lisp to close"
	while [[ `netstat --tcpip -pn 2>/dev/null | grep \:$YISTI_OLD_PORT | grep \ $YISTI_RUNNING_SERVER_PID\/ | wc -l` -gt 0 ]]; do
		echo -n "."
		sleep 2
	done
	echo ""
	echo "No connections remaining, killing obsolete Lisp"
	kill $YISTI_RUNNING_SCREEN_PID
fi

exit 0
