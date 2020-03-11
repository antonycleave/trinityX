/var/log/cluster-messages/*.messages {
  rotate 7
  daily
  compress
  missingok
  notifempty
  dateext
  dateformat .%Y-%m-%d
  dateyesterday
  postrotate
     /usr/bin/systemctl kill -s HUP rsyslog
  endscript
}
