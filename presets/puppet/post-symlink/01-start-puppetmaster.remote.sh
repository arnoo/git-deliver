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
    echo "Puppetmaster is running, and should not. Aborting."
    exit 2
    ;;
  3)
    echo "Puppetmaster is not running. Try to start it..."
    ;;
  *)
    echo "Unexpected return code from $STATUS, aborting."
    exit 2
    ;;
esac

/usr/bin/sudo -n $START >/dev/null

if [ $? -ne 0 ]; then
  echo "Error running $START, aborting."
  exit 3
fi

echo "Puppetmaster is now started."

exit 0

