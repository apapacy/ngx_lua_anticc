sudo /etc/init.d/networking restart
sudo service docker restart
docker exec -it nginx_production bash
nginx -t
nginx -s reload
docker exec -u www-data -i megabank_runtime app/console c:c
sudo /usr/local/openresty/bin/openresty -t
sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
