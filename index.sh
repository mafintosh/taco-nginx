#!/bin/bash

SOFT_EXIT=false
ENABLE_WEBSOCKETS=false
HELP=false
VERSION=false
HTTP_PORT=80
HTTPS_PORT=443
HTTP_ONLY=false
HTTPS_ONLY=false

while true; do
  case "$1" in
    --soft-exit)       SOFT_EXIT=true; shift ;;
    -s)                SOFT_EXIT=true; shift ;;
    --name)            SERVICE_NAME="$2"; shift; shift ;;
    -n)                SERVICE_NAME="$2"; shift; shift ;;
    --help)            HELP=true; shift ;;
    -h)                HELP=true; shift ;;
    --port)            PORT="$2"; shift; shift ;;
    -p)                PORT="$2"; shift; shift ;;
    --version)         VERSION=true; shift ;;
    -v)                VERSION=true; shift ;;
    --domain)          DOMAIN="$2"; shift; shift ;;
    --server-name)     DOMAIN="$2"; shift; shift ;;
    -d)                DOMAIN="$2"; shift; shift ;;
    --server-config)   SERVER_CONFIG="$2"; shift; shift ;;
    -c)                SERVER_CONFIG="$2"; shift; shift ;;
    --location-config) LOCATION_CONFIG="$2"; shift; shift ;;
    -l)                LOCATION_CONFIG="$2"; shift; shift ;;
    --http-port)       HTTP_PORT=$2; shift; shift ;;
    --https-port)      HTTPS_PORT=$2; shift; shift ;;
    --http-only)       HTTP_ONLY=true; shift ;;
    --https-only)      HTTPS_ONLY=true; shift ;;
    --static)          SERVE_STATIC="$2"; shift; shift ;;
    --autoindex)       AUTO_INDEX="autoindex on;"; shift ;;
    --websockets)      ENABLE_WEBSOCKETS=true; shift ;;
    -w)                ENABLE_WEBSOCKETS=true; shift ;;
    *)                 break ;;
  esac
done


if $VERSION; then
  printf "1.12.1\n"
  exit
fi

if $ENABLE_WEBSOCKETS; then
  WEBSOCKETS_LINE_1="proxy_set_header Upgrade \$http_upgrade;"
  WEBSOCKETS_LINE_2="proxy_set_header Connection \"upgrade\";"
fi

if $HELP || [ "$1$SERVE_STATIC" == "" ]; then
cat << EOF
Usage: taco-nginx [run-opts] command arg1 ...
  --name, -n           [service-name]
  --port, -p           [port]
  --server-name,-d     [nginx server name pattern]
  --server-config,-c   [add this file to the server config]
  --location-config,-l [add this file to the location config]
  --soft-exit, -s      [wait 5s when shutting down]
  --http-only          [only listen on http port]
  --https-only         [only listen on https port]
  --http-port          [default: 80]
  --https-port         [default: 443]
  --static             [path/to/folder to serve statically]
  --autoindex          [serve file listing when using --static]
  --websockets,w       [enable websocket support]
  --version, -v        [prints installed version]

EOF
  exit
fi

[ "$PORT" = "" ] && export PORT=$(echo "require('net').createServer().listen(0, function() { process.stdout.write(''+this.address().port); this.close() })" | node)
[ "$SERVICE_NAME" == "" ] && SERVICE_NAME=$(node -e "process.stdout.write(require('./package.json').name)" 2>/dev/null)

if [ "$SERVICE_NAME" == "" ]; then
  printf "You need to specify a name using --name [name] or adding a package.json\n"
  exit 1
fi

[ "$DOMAIN" == "" ] && DOMAIN=$SERVICE_NAME.*
[ -f "$SERVER_CONFIG" ] && SERVER_CONFIG_CONTENTS="$(cat $SERVER_CONFIG)"
[ -f "$LOCATION_CONFIG" ] && LOCATION_CONFIG_CONTENTS="$(cat $LOCATION_CONFIG)"
[ ""]

if [ ! -d /etc/nginx/conf.d ]; then
  printf "/etc/nginx/conf.d does not exist. Is nginx installed?\n"
  exit 2
fi

LISTEN_HTTPS="listen $HTTPS_PORT;"
LISTEN_HTTP="listen $HTTP_PORT;"
$HTTPS_ONLY && LISTEN_HTTP=""
$HTTP_ONLY && LISTEN_HTTPS=""

reload_nginx () {
  [ ! -O /etc/nginx/conf.d ] && SUDO_MAYBE=sudo
  $SUDO_MAYBE mv /tmp/nginx.$SERVICE_NAME.$PORT.conf /etc/nginx/conf.d/$SERVICE_NAME.conf
  $SUDO_MAYBE nginx -s reload
  trap on_exit EXIT
}

on_sigterm () {
  $SOFT_EXIT && sleep 5
  kill $PID
  wait $PID
}

on_exit () {
  $SUDO_MAYBE rm -f /etc/nginx/conf.d/$SERVICE_NAME.conf
  $SUDO_MAYBE nginx -s reload
}

on_static () {
cat << EOF > /tmp/nginx.$SERVICE_NAME.$PORT.conf
server {
  $LISTEN_HTTPS
  $LISTEN_HTTP
  server_name $DOMAIN;
  $SERVER_CONFIG_CONTENTS
  location / {
    $AUTO_INDEX
    root $(realpath "$SERVE_STATIC");
  }
}
EOF

  reload_nginx
  tail -f /dev/null
  exit $?
}

on_ready () {
cat << EOF > /tmp/nginx.$SERVICE_NAME.$PORT.conf
upstream $SERVICE_NAME {
  server 127.0.0.1:$PORT;
}
server {
  $LISTEN_HTTPS
  $LISTEN_HTTP
  server_name $DOMAIN;
  location / {
    proxy_pass http://$SERVICE_NAME;
    proxy_set_header X-Forwarded-For \$remote_addr;
    proxy_set_header Host \$host;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_http_version 1.1;
    client_max_body_size 0;
    $LOCATION_CONFIG_CONTENTS
    $WEBSOCKETS_LINE_1
    $WEBSOCKETS_LINE_2
  }
  $SERVER_CONFIG_CONTENTS
}
EOF

  reload_nginx
  wait $PID
  exit $?
}

if [ "$SERVE_STATIC" != "" ]; then
  on_static
else
  trap on_sigterm SIGTERM
  PATH="node_modules/.bin:$PATH"

  "$@" &
  PID=$!

  for i in {1..20}; do
    lsof -p $PID 2>/dev/null | grep "TCP \*:$PORT" 2>/dev/null >/dev/null && on_ready
    sleep 0.2
  done;

  on_ready
fi
