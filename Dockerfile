FROM python:2.7.12
MAINTAINER = Petrovich <xroot@yahoo.com>

EXPOSE 9696
ENV NEUTRON_VERSION 14.0.0.0b1
ENV NEUTRON_ADMIN_PASSWD passw0rd
ENV NEUTRON_DB_ROOT_PASSWD passw0rd
ENV NEUTRON_DB_PASSWD passw0rd

LABEL version="$NEUTRON_VERSION"
LABEL description="Openstack Neutron Docker Image Supporting HTTP/HTTPS"

RUN apt-get -y update \
    && apt-get install -y apache2 libapache2-mod-wsgi git memcached\
        libffi-dev python-dev libssl-dev mysql-client libldap2-dev libsasl2-dev\
    && apt-get -y clean

RUN git clone -b ${NEUTRON_VERSION} https://github.com/openstack/neutron.git

WORKDIR /neutron
RUN pip install -r requirements.txt && python setup.py install

RUN pip install osc-lib python-openstackclient PyMySql python-memcached \
    python-ldap ldappool
RUN mkdir -p /etc/neutron/plugins/ml2

COPY ./etc/neutron.conf /etc/neutron/neutron.conf
COPY ./etc/dhcp_agent.ini /etc/neutron
COPY ./etc/l3_agent.ini /etc/neutron
COPY ./etc/linuxbridge_agent.ini /etc/neutron
COPY ./etc/metadata_agent.ini /etc/neutron
COPY ./etc/ml2_conf.ini /etc/neutron/plugins/ml2

COPY neutron.sql /neutron.sql
COPY bootstrap.sh /bootstrap.sh
COPY ./neutron.wsgi.conf /etc/apache2/sites-available/neutron.conf

RUN cp /neutron/etc/api-paste.ini /etc/neutron

WORKDIR /root
CMD sh -x /bootstrap.sh
