#!/bin/bash

SOFT_EXIT=false
HELP=false
VERSION=false

while true; do
  case "$1" in
    --soft-exit) SOFT_EXIT=true; shift ;;
    -s)          SOFT_EXIT=true; shift ;;
    --name)      SERVICE_NAME="$2"; shift; shift ;;
    --n)         SERVICE_NAME="$2"; shift; shift ;;
    --help)      HELP=true; shift ;;
    -h)          HELP=true; shift ;;
    --port)      PORT="$2"; shift; shift ;;
    -p)          PORT="$2"; shift; shift ;;
    --version)   VERSION=true; shift ;;
    -v)          VERSION=true; shift ;;
    *)           break ;;
  esac
done

if $VERSION; then
  printf "1.0.0\n"
  exit
fi

if $HELP || [ "$1" == "" ]; then
cat << EOF
Usage: taco-nginx [run-opts] command arg1 ...
  --name, -n      [service-name]
  --port, -p      [port]
  --soft-exit, -s [wait 5s when shutting down]
  --version, -v   [prints installed version]

EOF
  exit
fi

[ "$PORT" = "" ] && export PORT=$(echo "require('net').createServer().listen(0, function() { process.stdout.write(''+this.address().port); this.close() })" | node)
[ "$SERVICE_NAME" == "" ] && SERVICE_NAME=$(node -e "process.stdout.write(require('./package.json').name)" 2>/dev/null)

if [ "$SERVICE_NAME" == "" ]; then
  printf "You need to specify a name using --name [name] or adding a package.json\n"
  exit 1
fi

if [ ! -d /etc/nginx/conf.d ]; then
  printf "/etc/nginx/conf.d does not exist. Is nginx installed?\n"
  exit 2
fi

on_exit () {
  $SOFT_EXIT && sleep 5
  kill $PID
  wait $PID
}

on_ready () {
cat << EOF > /tmp/nginx.$SERVICE_NAME.$PORT.conf
upstream $SERVICE_NAME {
  server 127.0.0.1:$PORT;
}
server {
  listen 80;
  server_name $SERVICE_NAME.*;
  location / {
    proxy_pass http://$SERVICE_NAME;
    proxy_set_header X-Forwarded-For \$remote_addr;
    proxy_buffering off;
  }
}
EOF

  [ ! -O /etc/nginx/conf.d ] && SUDO_MAYBE=sudo
  $SUDO_MAYBE mv /tmp/nginx.$SERVICE_NAME.$PORT.conf /etc/nginx/conf.d/$SERVICE_NAME.conf
  $SUDO_MAYBE nginx -s reload

  wait $PID
  exit $?
}

trap on_exit SIGTERM

"$@" &
PID=$!

for i in {1..20}; do
  lsof -p $PID 2>/dev/null | grep "TCP \*:$PORT" 2>/dev/null >/dev/null && on_ready
  sleep 0.2
done;

on_ready
