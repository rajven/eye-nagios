#!/usr/bin/perl

use FindBin '$Bin';
use lib "$Bin";
use DBI;
use File::Basename;
use File::Find;
use File::stat qw(:FIELDS);
use File::Spec::Functions;
use Sys::Hostname;
use DirHandle;
use Time::localtime;
use Fcntl;
use Tie::File;
use Data::Dumper;
use Net::Ping;
use Rstat::config;
use Rstat::main;
use Rstat::nagios;
use Rstat::mysql;

my %devices;
my %auths;

my %dependency;

my @netdev_list=get_records_sql($dbh,'SELECT * FROM devices WHERE deleted=0 and nagios=1');

##################################### Netdevices analyze ################################################
if (scalar(@netdev_list)>0) {
    foreach my $router (@netdev_list) {
        next if (!$router);
        my $ip = $router->{'ip'};
        $ip =~s/\/\d+$//g;
        my $device_id = 'netdev_'.$router->{'id'};
        $devices{$device_id}{ip}=$ip;
        $devices{$device_id}{community}=$router->{'community'};
        $devices{$device_id}{name} = $router->{'device_name'};
        $devices{$device_id}{device_model} = $router->{'device_model'};
        $devices{$device_id}{device_id} = $router->{'id'};
        $devices{$device_id}{snmp_version} = $router->{'snmp_version'};
        if ($devices{$device_id}{snmp_version} eq '2') { $devices{$device_id}{snmp_version}='2c'; }
        $devices{$device_id}{vendor_id} = $router->{'vendor_id'};
        if ($router->{'is_router'}) { $devices{$device_id}{type}='1'; } else { $devices{$device_id}{type}='2'; }
        $devices{$device_id}{rw_community}=$router->{'rw_community'};
        $devices{$device_id}{fdb_snmp_index}=$router->{'fdb_snmp_index'};
        $devices{$device_id}{user_id}=$router->{'user_id'};
        #get uplinks
        my $uplink_port = get_record_sql($dbh,"SELECT * FROM device_ports WHERE uplink=1 AND device_id=".$devices{$device_id}{device_id}." AND target_port_id>0 ORDER BY port DESC");
        if ($uplink_port and $uplink_port->{target_port_id}) {
            my $parent_uplink = get_record_sql($dbh,"SELECT * FROM device_ports WHERE id=".$uplink_port->{target_port_id}." ORDER BY id DESC");
            if ($parent_uplink and $parent_uplink->{device_id}) {
        	my $uplink_device = get_record_sql($dbh,"SELECT * FROM devices WHERE id=".$parent_uplink->{device_id}." AND nagios=1 AND deleted=0");
        	if ($uplink_device) {
        	    $devices{$device_id}{parent}='netdev_'.$uplink_device->{'id'}; 
        	    $devices{$device_id}{parent_name}=$uplink_device->{'device_name'};
        	    }
        	}
            my $uplink = get_record_sql($dbh,"SELECT * FROM device_ports WHERE id=".$uplink_port->{id}." ORDER BY id DESC");
    	    $devices{$device_id}{parent_downlink}=$parent_uplink;
    	    $devices{$device_id}{uplink}=$uplink;
            }
        #downlinks
        my @downlinks = get_records_sql($dbh,"SELECT * FROM device_ports WHERE device_id=".$devices{$device_id}{device_id}." and target_port_id>0 and uplink=0");
        foreach my $downlink_port (@downlinks) {
    	    my $downlink = get_record_sql($dbh,"SELECT * FROM device_ports WHERE id=".$downlink_port->{target_port_id});
    	    if ($downlink) {
    		my $downlink_device = get_record_sql($dbh,"SELECT * FROM devices WHERE id=".$downlink->{device_id});
    		if ($downlink_device) { $downlink_port->{downlink_name}=$downlink_device->{device_name}; }
		}
	    #id,port,snmp_index
            push(@{$devices{$device_id}{downlinks}},$downlink_port);
    	    }
	#custom ports
        my @custom_ports = get_records_sql($dbh,"SELECT * FROM device_ports WHERE device_id=".$devices{$device_id}{device_id}." and target_port_id=0 and uplink=0 and nagios=1");
        foreach my $downlink_port (@custom_ports) {
            #id,port,snmp_index,comment
	    push(@{$devices{$device_id}{downlinks}},$downlink_port);
    	    }
        }
    }

my @auth_list=get_records_sql($dbh,'SELECT * FROM User_auth WHERE deleted=0 and nagios=1');

##################################### User auth analyze ################################################

if (scalar(@auth_list)>0) {
    foreach my $auth (@auth_list) {
        next if (!$auth);
        my $ip = $auth->{'ip'};
        $ip =~s/\/\d+$//g;
        #skip doubles
        my $device_id = 'auth_'.$auth->{'id'};
        next if ($devices{$device_id});
        $devices{$device_id}{ip}=$ip;
        #get user
        my $login = get_record_sql($dbh,"SELECT * FROM User_list WHERE id=".$auth->{'user_id'});
        $devices{$device_id}{user_login} = $login->{login};
        $devices{$device_id}{user_fio} = $login->{fio};
	if ($login and $login->{ou_id}) { $devices{$device_id}{ou_id} = $login->{ou_id}; } else { $devices{$device_id}{ou_id} = 0; }
	#name
        if ($auth->{dns_name}) { $devices{$device_id}{name} = $auth->{dns_name}; }
        if (!$devices{$device_id}{name} and $auth->{dhcp_hostname}) { $devices{$device_id}{name} = $auth->{dhcp_hostname}; }
        if (!$devices{$device_id}{name}) {
    	    if ($auth->{comments}) {
    		$devices{$device_id}{name} = translit($auth->{comments});
    		$devices{$device_id}{name}=~s/\(/-/g;
    		$devices{$device_id}{name}=~s/\)/-/g;
    		$devices{$device_id}{name}=~s/--/-/g;
    		} else {
    		$devices{$device_id}{name} = $login->{login}."_".$auth->{id};
    		}
    	    }
        $devices{$device_id}{device_model} = $auth->{'host_model'};
        $devices{$device_id}{auth_id} = $auth->{'id'};
        $devices{$device_id}{nagios_handler} = $auth->{'nagios_handler'};
        $devices{$device_id}{link_check} = $auth->{'link_check'};
        $devices{$device_id}{type}='3';
        $devices{$device_id}{user_id}=$auth->{'user_id'};
        #get uplinks
        my $uplink_port = get_record_sql($dbh,"SELECT * FROM connections WHERE auth_id=".$auth->{'id'});
        if ($uplink_port and $uplink_port->{port_id}) {
            my $uplink = get_record_sql($dbh,"SELECT * FROM device_ports WHERE id=".$uplink_port->{port_id});
            if ($uplink and $uplink->{device_id} and $devices{'netdev_'.$uplink->{'device_id'}}) {
        	$devices{$device_id}{parent}='netdev_'.$uplink->{'device_id'};
                $devices{$device_id}{parent_port} = $uplink->{port};
	        $devices{$device_id}{parent_port_snmp_index} = $uplink->{snmp_index};
        	$devices{$device_id}{parent_name}=$devices{$devices{$device_id}{parent}}->{'name'};
        	$devices{$device_id}{parent_snmp_version}=$devices{$devices{$device_id}{parent}}->{'snmp_version'};
        	$devices{$device_id}{parent_community}=$devices{$devices{$device_id}{parent}}->{'community'};
        	}
            }
        }
    }

foreach my $dir (@cfg_dirs) {
    mkdir $dir unless (-d $dir);
    unlink glob "$dir/*.cfg";
}

##################################### Switches config ################################################

foreach my $device_id (keys %devices) {
my $device = $devices{$device_id};
next if (!$device->{ip});
if ($device->{parent_name}) { push(@{$dependency{$device->{parent_name}}},$device->{name}); }
print_nagios_cfg($device);
}

####################### Dependency ###########################

open(FH,">","/etc/nagios/dependency/dep_hosts.cfg");
foreach my $device_name (keys %dependency) {
my @dep_list=@{$dependency{$device_name}};
if (@dep_list and scalar(@dep_list)) {
    my $dep_hosts;
    foreach my $dep_host (@dep_list) {
	next if (!$dep_host);
	$dep_hosts = $dep_hosts.",".$dep_host;
	}
    next if (!$dep_hosts);
    $dep_hosts=~s/^,//;
    print(FH "define hostdependency {\n");
    print(FH "       host_name			$device_name\n");
    print(FH "       dependent_host_name	$dep_hosts\n");
    print(FH "       execution_failure_criteria      n,u\n");
    print(FH "       notification_failure_criteria   d,u\n");
    print(FH "       }\n");
    }
}
close(FH);

exit
