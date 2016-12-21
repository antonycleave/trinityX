#!/bin/bash

######################################################################
# TrinityX
# Copyright (c) 2016  ClusterVision B.V.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License (included with the sources) for more
# details.
######################################################################


display_var TRIX_CTRL{1,2}_IP BIND_{FORWARDERS,DISABLE_DNSSEC}

# BIND (DNS server) configuration

if flag_is_set HA && flag_is_unset PRIMARY_INSTALL; then
    /usr/bin/rm -rf /var/named
    /usr/bin/rm -rf /etc/named.conf
    /usr/bin/rm -rf /etc/named.forwarders.conf
    /usr/bin/ln -fs /trinity/local/var/named /var/named
    /usr/bin/ln -fs /trinity/local/etc/named.conf /etc/named.conf
    /usr/bin/ln -fs /trinity/local/etc/named.forwarders.conf /etc/named.forwarders.conf
    exit 0
fi

if flag_is_set HA && flag_is_set PRIMARY_INSTALL; then
    /usr/bin/mkdir -p /trinity/local/etc
    /usr/bin/mkdir -p /trinity/local/var
    /usr/bin/mv /etc/named.conf /trinity/local/etc/
    /usr/bin/mv /var/named /trinity/local/var/
    /usr/bin/ln -fs /trinity/local/etc/named.conf /etc/named.conf
    /usr/bin/ln -fs /trinity/local/etc/named.forwarders.conf /etc/named.forwarders.conf
    /usr/bin/ln -fs /trinity/local/var/named /var/named
fi

echo_info 'Make named listen for requests on all interfaces'
sed -i -e 's/\(.*listen-on port 53 { \).*\( };\)/\1any;\2/' /etc/named.conf

echo_info 'Make named accept queries from all nodes that are not blocked by the firewall'
sed -i -e 's,\(.*allow-query\s.*{ \).*\( };\),\1any;\2,' /etc/named.conf


echo_info "Use this DNS server as the default resolver"

sed -i "s,^\(search .*\),# \1,g" /etc/resolv.conf
sed -i "s,^\(nameserver .*\),# \1,g" /etc/resolv.conf

append_line /etc/resolv.conf "search cluster ipmi"

for RESOLVER in TRIX_CTRL{1,2}_IP; do
    if [[ -v $RESOLVER ]] ; then
        append_line /etc/resolv.conf "nameserver "${!RESOLVER}""
    fi
done


echo_info 'Setting up dhclient to avoid overwriting our configuration'

cp "${POST_FILEDIR}/dhclient-enter-hooks" /etc/dhcp


if flag_is_set BIND_FORWARDERS ; then
    echo_info 'Setting up the DNS forwarders'

    # Create a forwarders files that we will include in the main config file
    (
    echo '// ICS BIND DNS forwarders'
    echo 'forwarders {'
    for i in $BIND_FORWARDERS ; do
        echo -e "\t${i};"
    done
    echo -e '};'
    ) | tee /etc/named.forwarders.conf

    # And include it
    if ! grep -q /etc/named.forwarders.conf /etc/named.conf ; then
        sed -i '/recursion yes/a \\tinclude "/etc/named.forwarders.conf";' /etc/named.conf
    fi
fi


if flag_is_set BIND_DISABLE_DNSSEC ; then
    echo_info 'Disabling DNSSEC'
    sed -i 's/^\([[:space:]]\+\)\(dnssec-enable.*\)/\1\/\/\2/g' /etc/named.conf
fi


echo_info 'Enabling and starting the named service'
systemctl enable named
systemctl restart named

if flag_is_set HA && flag_is_set PRIMARY_INSTALL; then
    /usr/bin/systemctl disable named
    TMPFILE=$(/usr/bin/mktemp -p /root pacemaker_named.XXXX)
    /usr/sbin/pcs cluster cib ${TMPFILE}
    /usr/sbin/pcs -f ${TMPFILE} resource delete named || true
    /usr/sbin/pcs -f ${TMPFILE} resource create named systemd:named --force
    /usr/sbin/pcs -f ${TMPFILE} constraint colocation add named with trinity-fs
    /usr/sbin/pcs -f ${TMPFILE} constraint order start trinity-fs then start named
    /usr/sbin/pcs cluster cib-push ${TMPFILE}
fi
