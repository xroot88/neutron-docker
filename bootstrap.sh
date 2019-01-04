#!/usr/bin/env bash

TLS_ENABLED=${TLS_ENABLED:-false}
if $TLS_ENABLED; then
    HTTP="https"
    CN=${CN:-$HOSTNAME}
    # generate pem and crt files
    mkdir -p /etc/apache2/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/apache2/ssl/apache.key -out /etc/apache2/ssl/apache.crt \
        -subj "/C=$CONUTRY/ST=$STATE/L=$LOCALITY/O=$ORG/OU=$ORG_UNIT/CN=$CN"
else
    HTTP="http"
fi

NEUTRON_DB_ROOT_PASSWD=$NEUTRON_DB_ROOT_PASSWD_IF_REMOTED

addgroup --system neutron >/dev/null || true
adduser --quiet --system --home /var/lib/neutron \
        --no-create-home --ingroup neutron --shell /bin/false \
        neutron || true

if [ "$(id -gn neutron)"  = "nogroup" ]
then
    usermod -g neutron neutron
fi

# create appropriate directories
mkdir -p /var/lib/neutron/ /etc/neutron/ /var/log/neutron/

# change the permissions on key directories
chown neutron:neutron -R /var/lib/neutron/ /etc/neutron/ /var/log/neutron/
chmod 0700 /var/lib/neutron/ /var/log/neutron/ /etc/neutron/

# Neutron Database and user
sed -i 's|NEUTRON_DB_PASSWD|'"$NEUTRON_DB_PASSWD"'|g' /neutron.sql
mysql -uroot -p$NEUTRON_DB_ROOT_PASSWD -h $NEUTRON_DB_HOST < /neutron.sql

# Update neutron.conf
sed -i "s/NEUTRON_DB_PASSWD/$NEUTRON_DB_PASSWD/g" /etc/neutron/neutron.conf
sed -i "s/NEUTRON_DB_HOST/$NEUTRON_DB_HOST/g" /etc/neutron/neutron.conf
sed -i "s/NEUTRON_ADMIN_PASSWD/$NEUTRON_ADMIN_PASSWD/g" /etc/neutron/neutron.conf
sed -i "s/NOVA_ADMIN_PASSWD/$NOVA_ADMIN_PASSWD/g" /etc/neutron/neutron.conf
sed -i "s/RABBIT_HOST/$RABBIT_HOST/g" /etc/neutron/neutron.conf
sed -i "s/RABBIT_USER/$RABBIT_USER/g" /etc/neutron/neutron.conf
sed -i "s/RABBIT_PASSWD/$RABBIT_PASSWD/g" /etc/neutron/neutron.conf
sed -i "s/KEYSTONE_HOST/$HTTP:\/\/${KEYSTONE_HOST}/g" /etc/neutron/neutron.conf
sed -i "s/MEMCACHED_HOST/${MEMCACHED_HOST}/g" /etc/neutron/neutron.conf

sed -i "s/PROVIDER_INTERFACE_NAME/$PROVIDER_INTERFACE_NAME/g" /etc/neutron/linuxbridge_agent.ini
sed -i "s/OVERLAY_INTERFACE_IP_ADDRESS/$OVERLAY_INTERFACE_IP_ADDRESS/g" /etc/neutron/linuxbridge_agent.ini

sed -i "s/KEYSTONE_HOST/$KEYSTONE_HOST/g" /etc/neutron/metadata_agent.ini
sed -i "s/METADATA_SECRET/$METADATA_SECRET/g" /etc/neutron/metadata_agent.ini

cat /etc/neutron/neutron.conf
cat /etc/neutron/linuxbridge_agent.ini
cat /etc/neutron/metadata_agent.ini

ip a
ping -c 3 $RABBIT_HOST

# Populate neutron database
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron


# Write openrc to disk
cat > /root/openrc <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=${NEUTRON_ADMIN_PASSWD}
export OS_AUTH_URL=$HTTP://${KEYSTONE_HOST}:35357/v3
export OS_IDENTITY_API_VERSION=3
EOF

. /root/openrc
openstack user create --domain default --password ${NEUTRON_ADMIN_PASSWD}  neutron
openstack role add --project service --user neutron admin
openstack service show network && echo 'Service network already exists in db' || openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region AUS network public $HTTP://$HOSTNAME:9696
openstack endpoint create --region AUS network internal $HTTP://$HOSTNAME:9696
openstack endpoint create --region AUS network admin $HTTP://$HOSTNAME:9696

# Configure Apache2
echo "ServerName $HOSTNAME" >> /etc/apache2/apache2.conf

# if TLS is enabled
if $TLS_ENABLED; then
echo "export OS_CACERT=/etc/apache2/ssl/apache.crt" >> /root/openrc
a2enmod ssl
sed -i '/<VirtualHost/a \
    SSLEngine on \
    SSLCertificateFile /etc/apache2/ssl/apache.crt \
    SSLCertificateKeyFile /etc/apache2/ssl/apache.key \
    ' /etc/apache2/sites-available/neutron.conf
fi

# ensite neutron and start apache2
a2ensite neutron
id
apache2ctl start
find / -name neutron-rpc-server
# Start the neutron RPC server manually
/usr/local/bin/neutron-rpc-server --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini
