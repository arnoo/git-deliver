#!/bin/bash

IS=/etc/init.d/puppetmaster
STOP="$IS stop"
START="$IS start"

if [ -f /var/run/puppet/master.pid ];
then
    ps -p `cat /var/run/puppet/master.pid` >/dev/null
	if [ $? -eq 0 ]; then
      echo "Puppetmaster is running, and should not. Aborting."
      exit 2
    fi
fi

/usr/bin/sudo -n $START >/dev/null

res=$?
if [ $res -ne 0 ]; then
  echo "Error running $START (status $res), aborting."
  exit 3
fi

echo "Puppetmaster is now started."

exit 0

