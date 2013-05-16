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

/usr/bin/sudo -n /bin/ps 2>&1 >/dev/null
if [ $? -ne 0 ]; then
  echo "You don't have the proper rights to run \"/usr/bin/sudo -n ps\". Add something like \"yourlogin   ALL=(ALL:ALL) NOPASSWD: /bin/ps\" to your sudoers file"
  exit 3
fi

# test service pid (sudo init.d
# 1 = not running
# 0 = running
/usr/bin/sudo -n /bin/ps -p `cat /var/run/puppet/master.pid` >/dev/null
res=$?
case $res in
  1)
    echo "Puppetmaster is not running."
    exit 0
    ;;
  0)
    echo "Puppetmaster is running. Try to stop it..."
    ;;
  *)
    echo "Unexpected return code from ps ($res), aborting."
    exit 2
    ;;
esac

/usr/bin/sudo -n $STOP >/dev/null
res=$?

case $res in
  1)
    echo "You don't have to proper rights to run $IS. Add something like \"yourlogin   ALL=(ALL:ALL) NOPASSWD: $IS\" to your sudoers file"
    exit 1
    ;;
  0)
    echo "Puppetmaster is now stopped."
    exit 0
    ;;
  *)
    echo "Unexpected return code from $STOP ($res), aborting."
    exit 2
    ;;
esac