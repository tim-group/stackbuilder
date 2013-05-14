#!/bin/bash
if [ -f "/etc/init.d/apache2-puppetmaster" ]; then
  /etc/init.d/apache2-puppetmaster status >/dev/null 2>&1
  if [ $? -eq "0" ]; then
    /etc/init.d/apache2-puppetmaster restart
  fi
fi

exit 0

