#!/bin/bash
#################################################################################
#
#################################################################################
home=/opt/zbxtools/zbxhistory
cd $home

zabbix_server='http://localhost:8191/zabbix/api_jsonrpc.php'
zabbix_user='admin'
zabbix_password='zabbix'
zabbix_host='zabbix-server'
zabbix_itemkey='vm.memory.size.pused'

/usr/bin/perl $home/zbxhistory.pl -s "$zabbix_server" -u "$zabbix_user" -p "$zabbix_password" -z "$zabbix_host" -i "$zabbix_itemkey" "$@"
