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
use eyelib::config;
use eyelib::main;
use eyelib::nagios;
use eyelib::mysql;
use Fcntl qw(:flock);

open(SELF,"<",$0) or die "Cannot open $0 - $!";
flock(SELF, LOCK_EX|LOCK_NB) or exit 1;

my %devices;
my %auths;

my %dependency;

my $nagios_devices = "/etc/snmp/devices.cfg";

my @OU_list = get_records_sql($dbh,"SELECT * FROM OU");
my %ou;
my @cfg_dirs = ();
foreach my $row (@OU_list) {
next if (!$row->{nagios_dir});
if ($row->{nagios_dir}!~/^$config_ref{nagios_dir}/) { $row->{nagios_dir}=$config_ref{nagios_dir}.'/'.$row->{nagios_dir}; }
$row->{nagios_dir}=~s/\/$//;
$ou{$row->{id}}=$row;
push(@cfg_dirs,$row->{nagios_dir});
}

@cfg_dirs = uniq(@cfg_dirs);

my @Model_list = get_records_sql($dbh,"SELECT * FROM device_models");
my %models;
foreach my $row (@Model_list) {
$models{$row->{id}}=$row;
}

#switches & routers only
my @netdev_list=get_records_sql($dbh,'SELECT * FROM devices WHERE deleted=0 and nagios=1 and device_type<=2');

##################################### Netdevices analyze ################################################
if (scalar(@netdev_list)>0) {
    foreach my $router (@netdev_list) {
        next if (!$router);
        my $ip = $router->{'ip'};
        $ip =~s/\/\d+$//g;
        my $device_id = 'netdev_'.$router->{'id'};
        $devices{$device_id}{ip}=$ip;
        $devices{$device_id}{community}=$router->{'community'} || $config_ref{snmp_default_community};
        $devices{$device_id}{description}=translit($router->{'comment'});
        $devices{$device_id}{name} = $router->{'device_name'};
        $devices{$device_id}{device_model_id} = $router->{'device_model_id'};
        if ($router->{'device_model_id'}) { $devices{$device_id}{device_model} = $models{$router->{'device_model_id'}};  }
        $devices{$device_id}{device_id} = $router->{'id'};
        $devices{$device_id}{snmp_version} = $router->{'snmp_version'} || $config_ref{snmp_default_version};
        if ($devices{$device_id}{snmp_version} eq '2') { $devices{$device_id}{snmp_version}='2c'; }
        $devices{$device_id}{vendor_id} = $router->{'vendor_id'};
        $devices{$device_id}{ou_id} = 0;
        #1 - switch; 2 - router; 3 - auth
        #NOT DEVICE TYPE IN DB!!!
        $devices{$device_id}{type}='1';
        $devices{$device_id}{ou_id}='7';
        if ($router->{'device_type'} eq 2) {
            $devices{$device_id}{type}='2'; 
            $devices{$device_id}{ou_id}='10';
            }
	if ($router->{'user_id'}) {
            #get user
	    my $login = get_record_sql($dbh,"SELECT * FROM User_list WHERE id=".$router->{'user_id'});
	    if ($login and $login->{ou_id} and $ou{$login->{ou_id}}->{nagios_dir}) { $devices{$device_id}{ou_id} = $login->{ou_id}; }
            }
        $devices{$device_id}{ou}=$ou{$devices{$device_id}{ou_id}};

        if (!$devices{$device_id}{ou}->{nagios_dir}) {
    	    if ($devices{$device_id}{type} eq '1') { $devices{$device_id}{ou}->{nagios_dir}='switches'; }
    	    if ($devices{$device_id}{type} eq '2') { $devices{$device_id}{ou}->{nagios_dir}='routers'; }
    	    }

	$devices{$device_id}{snmp_version}=$router->{'snmp_version'} || $config_ref{snmp_default_version};
	$devices{$device_id}{community}=$router->{'community'} || $config_ref{snmp_default_community};
        $devices{$device_id}{rw_community}=$router->{'rw_community'} || $config_ref{snmp_default_community};
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

	#skip user device with few ip
        my $auth_count = get_count_records($dbh,"User_auth","user_id=".$auth->{'user_id'}." AND deleted=0");
        next if ($auth_count>1);

	#skip switches and routers
        my $auth_device = get_record_sql($dbh,"SELECT * FROM devices WHERE user_id=".$auth->{'user_id'});
	next if ($auth_device and $auth_device->{device_type}<=2);

	#snmp parameters
	if ($auth_device) {
		$devices{$device_id}{snmp_version}=$auth_device->{snmp_version};
		$devices{$device_id}{community}=$auth_device->{community};
		$devices{$device_id}{rw_community}=$auth_device->{rw_community};
		$devices{$device_id}{name}=$auth_device->{device_name};
		} else {
		$devices{$device_id}{snmp_version}=$config_ref{snmp_default_version};
		$devices{$device_id}{community}=$config_ref{snmp_default_community};
		$devices{$device_id}{rw_community}=$config_ref{snmp_default_community};
		}

        $devices{$device_id}{ip}=$ip;

        #get user
        my $login = get_record_sql($dbh,"SELECT * FROM User_list WHERE id=".$auth->{'user_id'});
    
        $devices{$device_id}{user_login} = $login->{login};
        $devices{$device_id}{user_fio} = $login->{fio};
        $devices{$device_id}{ou_id} = 0;
	if ($login and $login->{ou_id} and $ou{$login->{ou_id}}->{nagios_dir}) { $devices{$device_id}{ou_id} = $login->{ou_id}; }
        $devices{$device_id}{ou}=$ou{$devices{$device_id}{ou_id}};
        
        $devices{$device_id}{device_model_id} = $auth_device->{'device_model_id'};
        if ($auth_device->{'device_model_id'}) { $devices{$device_id}{device_model} = $models{$auth_device->{'device_model_id'}}; }
        
	#name
        if (!$devices{$device_id}{name} and $auth->{dns_name}) { $devices{$device_id}{name} = $auth->{dns_name}; }
        if (!$devices{$device_id}{name}) {
    	    if ($login->{login}) {
    		$devices{$device_id}{name} = translit($login->{login});
    		$devices{$device_id}{name}=~s/\(/-/g;
    		$devices{$device_id}{name}=~s/\)/-/g;
    		$devices{$device_id}{name}=~s/--/-/g;
    		} else {
    		$devices{$device_id}{name} = "auth_id_".$auth->{id};
    		}
    	    }
        $devices{$device_id}{description}=translit($auth->{'comments'}) || $devices{$device_id}{name};
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
    next if ($dir eq '/');
    next if ($dir eq '/etc');
    next if ($dir eq $config_ref{nagios_dir});
    mkdir $dir unless (-d $dir);
    unlink glob "$dir/*.cfg";
}

##################################### Switches config ################################################

write_to_file($nagios_devices,"#lisf of device for nagios",0);

foreach my $device_id (keys %devices) {
my $device = $devices{$device_id};
next if (!$device->{ip});
if ($device->{parent_name}) { push(@{$dependency{$device->{parent_name}}},$device->{name}); }
print_nagios_cfg($device);
write_to_file($nagios_devices,'$devices{"'.$device->{'ip'}.'"}{"hostname"}="'.$device->{'name'}.'";',1);
}

####################### Dependency ###########################

open(FH,">",$config_ref{nagios_dir}."/dependency/dep_hosts.cfg");
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
