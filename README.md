# Neutron Docker


This repo is used to host a bunldle to create a docker container (based on
`Python 2.7.12`) running Neutron.

Neutron is an OpenStack service that provides API client authentication,
service discovery, and distributed multi-tenant authorization by implementing
[OpenStack’s Identity API](http://specs.openstack.org/openstack/neutron-specs/).


# What can this docker image do ?

* Running Neutron with **http** (default) or
    **https** (by passing `-e TLS_ENABLED=true`,
    see more in [Environment Variables Explanations](https://github.com/dixudx/neutron-docker#environment-variables-explanations)) enabled;
* Uses the **Apache Web Server** with `mod_wsgi` to serve Identity service
    requests on port `5000` and `35357`;
* Supports remote mysql database;
* Utilizes **Memcached** to store tokens, reducing the burden of MySQL database;
* Customizes/Builds your own Neutron docker image by editing the value
    of `NEUTRON_VERSION` in `Dockerfile`;


# How to get the image ?

* Build your own Neutron version using Dockerfile

    You can find more [Neutron release version](https://github.com/openstack/neutron/releases#).

    ```sh
    $ git clone https://github.com/xroot88/neutron-docker.git
    $ cd neutron-docker
    $ # edit the value of NEUTRON_VERSION to your favorite Neutron
    $ # release version
    $ vim Dockerfile
    $ docker build -t neutron:NEUTRON_VERSION ./
    ```

    **WARNING: Pay attention to the dependencies. You may need to specify
    dependency versions explicitly.**

# How to run the container

## Environment Variables Explanations

| Environment Variables              | Default Value | Editable when starting a container                      | Description                                                                                      |
|------------------------------------|---------------|---------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| NEUTRON_VERSION                   | 14.0.0.0b1     | False. Built in Dockerfile unless rebuilding the image. | The release version of Neutron.You can find more at https://github.com/openstack/neutron/tags.   |
| NEUTRON_ADMIN_PASSWD              | passw0rd      | True                                                    | The Neutron admin user password;                                                                  |
| NEUTRON_DB_ROOT_PASSWD            | passw0rd      | False. Built in Dockerfile unless rebuilding the image. | Neutron MySQL (default localhost) database root user password;                                    |
| NEUTRON_DB_PASSWD                 | passw0rd      | True                                                    | Neutron MySQL (default localhost) database neutron user password;                                 |
| TLS_ENABLED                       | false         | True                                                    | Whether to enable tls/https;                                                                      |
| NEUTRON_DB_HOST                   |               | True                                                    | MySQL remote database host; Combined with NEUTRON_DB_ROOT_PASSWD_IF_REMOTED                       |
| NEUTRON_DB_ROOT_PASSWD_IF_REMOTED |               | True                                                    | MySQL remote database root user password; Combined with NEUTRON_DB_HOST                           |
| PROVIDER_INTERFACE_NAME           |               | True                                                    | provider physical network interface name, such as eth0                                            |
| OVERLAY_INTERFACE_IP_ADDRESS      |               | True                                                    | mgmtnet IP address                                                                                |
| METADATA_SECRET                   |               | True                                                    | metadata proxy shared secret                                                                      |
| RABBIT_HOST                       |               | True                                                    | hostname/IP of the rabbitmq server                                                                |
| RABBIT_USER                       |               | True                                                    | rabbitmq user name                                                                                |
| RABBIT_PASSWD                     |               | True                                                    | rabbitmq user password                                                                            |
| NOVA_ADMIN_PASSWD                 |               | True                                                    | nova user password                                                                                |

## CSR (Certificate Signing Request) Environment Variables

If you've enabled `TLS_ENABLED` (with `-e TLS_ENABLED=true`), below environment
variables have to be noticed. You can just ignore them if you
don't want to make any further customizations.

| Environment Name | Default Value | Meaning             | Example         |
|------------------|---------------|---------------------|-----------------|
| CONUTRY          | NULL          | Country             | GB              |
| STATE            | NULL          | State               | London          |
| LOCALITY         | NULL          | Location            | London          |
| ORG              | NULL          | Organization        | Global Security |
| ORG_UNIT         | NULL          | Organizational Unit | IT Department   |
| CN               | The Hostname  | Common Name         | example.com     |

**Note**: *Be aware of `CN` (the default value is `$hostname`). You'd better
not change it to other value.*


**Note**: *You can also copy the `/root/openrc` to your other servers. After replacing
`OS_AUTH_URL` to the corresponding url, you can access the neutron service
from other servers after sourcing it.*

You can copy `/root/openrc` in your container to your host server,
and replace `OS_CACERT` to this `$pwd/apache/ssl/apache.crt`
(replace `$pwd` with your real directory path).
So that you access the neutron services using openstack python client
( `pip install python-openstackclient` ) from outer of the the container.

**Note**: *On your host server,
you may also need to add `myneutron.com` to `/etc/hosts`.*


# Reference

* [Neutron, the OpenStack Identity Service](http://docs.openstack.org/developer/neutron/)
* [Installing Neutron](http://docs.openstack.org/developer/neutron/installing.html)

# alexm notes:

## Prereqs

Unless you are planning to use a different keystone service, firstly, clone, build, and start git@github.com:xroot88/keystone-docker.git


Build the neutron container:

```sh
$ sudo docker build -t neutron:14.0.0.0b1 ./
```

The docker host must be connected to these three networks: Tenant, Management, and External.
* Tenant network is used to communicate among openstack containers
* Management network is used for management purposes, i.e. logins, signaling, etc
* External network connects to the internet.

Let's assume that
extnet is eth0
mgmtnet is eth1
tenantnet is eth2

1. Create docker bridged networks:

```sh
$sudo docker network create -d macvlan --subnet=10.0.0.0/24 --gateway=10.0.0.1 -o parent=eth1 mgmtnet
$ sudo docker network create -d macvlan --subnet=10.0.1.0/24 --gateway=10.0.1.1 -o parent=eth2 tenantnet
$ sudo docker network list
```

2. Create the container:

```sh
sudo docker create -p 9696:9696 -e PROVIDER_INTERFACE_NAME=eth0 -e OVERLAY_INTERFACE_IP_ADDRESS=eth2 -e METADATA_SECRET=cisco123 -e RABBIT_HOST=192.168.2.7 -e RABBIT_USER=rabbit -e RABBIT_PASSWD=cisco123 -e NOVA_ADMIN_PASSWD=cisco123 -e NEUTRON_DB_HOST=192.168.2.6 -e NEUTRON_DB_ROOT_PASSWD_IF_REMOTED=cisco123 -e MEMCACHED_HOST=keystone.ghettocoders.com -e KEYSTONE_HOST=keystone.ghettocoders.com --name neutron01 --hostname neutron.ghettocoders.com --link keystone01 -it neutron:14.0.0.0b1

```

3. Attach the bridge, tenantnet, and mgmtnet to the container:

```sh
sudo docker network connect bridge neutron01
sudo docker network connect tenantnet neutron01
sudo docker network connect mgmtnet neutron01
```

## Start the container

```sh
$ sudo docker start -i neutron01
$ sudo docker exec -it neutron01 bash
container-id# ip a
should see all three network interfaces attached and UP here.
container-id# source /root/openrc
container-id# openstack user list
container-id# openstack token issue
```
