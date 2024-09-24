#!/bin/bash

nginxfile="nginx.conf"
nginxaccess="/app/access.log"

cat > $nginxfile << EOM
events {
  worker_connections  1024;
}
http {
  map \$http_x_spcs_authorization \$authz {
    '~.' \$http_x_spcs_authorization;
    default '';
  }

  error_log stderr;
  server {
    listen 80;
    listen [::]:80;
    server_name localhost;
    access_log $nginxaccess;

EOM

while [ $# -gt 0 ]
do
        dp="$1"
        IFS='=' read -ra pieces <<< "$dp"
        echo "Path: ${pieces[0]} => ${pieces[1]}"
        cat >> $nginxfile << EOM
    location ${pieces[0]} {
        sub_filter '</head>' '<script src="//unpkg.com/xhook@latest/dist/xhook.min.js"></script> <script>xhook.before(function(request) { if ("Authorization" in request.headers) {request.headers["X-SPCS-Authorization"]=request.headers["Authorization"] }});</script>   </head>';
EOM
        if [ "${pieces[0]}" != "/" ]; then
            cat >> $nginxfile << EOM
        rewrite ${pieces[0]}/(.*) /\$1 break;
EOM
        fi
        cat >> $nginxfile << EOM
        proxy_pass ${pieces[1]};
        proxy_set_header Authorization \$authz;
    }
EOM
        shift
done


cat >> $nginxfile << EOM

  } 
}
EOM

cat $nginxfile

# Start nginx
cp $nginxfile /etc/nginx/nginx.conf
touch $nginxaccess
tail -f $nginxaccess 1>&2 &
exec nginx -g 'daemon off;'
