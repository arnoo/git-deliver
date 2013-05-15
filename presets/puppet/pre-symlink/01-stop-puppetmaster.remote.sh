#!/bin/bash

IS=/etc/init.d/puppetmaster
STATUS="$IS status"
STOP="$IS stop"
START="$IS start"

if [ ! -f /var/run/puppet/master.pid ];
then
    echo "Puppetmaster is not running."
    exit 0
fi

# initial test on pid, because some times sudo return code in the what is document below
# 1 = not running
# 0 = running
ps -p `cat /var/run/puppet/master.pid` >/dev/null
case $? in
  1)
    echo "Puppetmaster is not running."
    exit 0
    ;;
  0)
    echo "Puppetmaster is running. Try to stop it..."
    ;;
  *)
    echo "Unexpected return code from ps, aborting."
    exit 2
    ;;
esac

/usr/bin/sudo -n $STOP >/dev/null

case $? in
  1)
    echo "You don't have to proper rights to run $IS. Add something like \"yourlogin   ALL=(ALL:ALL) NOPASSWD: $IS\" to your sudoers file"
    exit 1
    ;;
  0)
    echo "Puppetmaster is now stopped."
    exit 0
    ;;
  *)
    echo "Unexpected return code from $STOP, aborting."
    exit 2
    ;;
esac



