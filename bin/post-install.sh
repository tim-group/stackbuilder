#!/bin/bash
if [ -f "/etc/init.d/apache2-puppetmaster" ]; then
  /etc/init.d/apache2-puppetmaster status >/dev/null 2>&1
  if [ $? -eq "0" ]; then
    x=$(netstat -nalp | grep 8140 | grep ESTABLISHED | wc -l)
    while [ $x -ge 0 ]
    do
      echo "Waiting for puppetmaster connections to drop to 0, currently $x"
      x=$(netstat -nalp | grep 8140 | grep ESTABLISHED | wc -l)
    done
    /etc/init.d/apache2-puppetmaster restart
  fi
fi

exit 0

