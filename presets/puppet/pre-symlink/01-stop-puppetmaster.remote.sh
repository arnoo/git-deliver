#!/bin/bash

IS=/etc/init.d/puppetmaster
STATUS="$IS status"
STOP="$IS stop"
START="$IS start"

# 1 = no right to do this
# 0 = running
# 3 = stopped
/usr/bin/sudo -n $STATUS >/dev/null

case $? in
  1)
    echo "You don't have to proper rights to run $IS. Add something like \"yourlogin   ALL=(ALL:ALL) NOPASSWD: $IS\" to your sudoers file"
    exit 1
    ;;
  0)
    echo "Puppetmaster is running. Try to stop it..."
    ;;
  3)
    echo "Puppetmaster is not running."
    exit 0
    ;;
  *)
    echo "Unexpected return code from $STATUS, aborting."
    exit 2
    ;;
esac

/usr/bin/sudo -n $STOP >/dev/null

if [ $? -ne 0 ]; then
  echo "Error running $STOP, aborting."
  exit 3
fi

echo "Puppetmaster is now stopped."

exit 0

