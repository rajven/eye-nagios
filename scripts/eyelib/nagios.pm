package eyelib::nagios;

#use v5.28;
use utf8;
use open ":encoding(utf8)";
no if $] >= 5.018, warnings =>  "experimental::smartmatch";
use strict;
use English;
use FindBin '$Bin';
use lib "$Bin";
use base 'Exporter';
use vars qw(@EXPORT @ISA);
use eyelib::config;
use eyelib::main;
use eyelib::mysql;
use Time::Local;
use Data::Dumper;

@ISA = qw(Exporter);
@EXPORT = qw(
nagios_send_command
nagios_host_svc_disable
nagios_host_svc_enable
print_nagios_cfg
@cfg_dirs
);

BEGIN
{

#---------------------------------------------------------------------------------

sub nagios_send_command {
my $command = shift;
next if (!$command);
if (!-e $config_ref{nagios_cmd}) { die("Command socket $config_ref{nagios_cmd} not found!"); }
log_info("Send command: $command to $config_ref{nagios_cmd}");
open(FH, ">> $config_ref{nagios_cmd}");
print FH "$command\n";
close(FH);
}

#---------------------------------------------------------------------------------

sub nagios_host_svc_disable {
my $hostname = shift;
my $full = shift || 0;
my $utime = timelocal(localtime());
my $cmd = "[$utime] DISABLE_HOST_SVC_CHECKS;$hostname";
#dont run!!!
#check nagios option work?
#nagios_send_command($cmd);
if ($full) {
    $cmd = "[$utime] DISABLE_ALL_NOTIFICATIONS_BEYOND_HOST;$hostname";
    nagios_send_command($cmd);
    }
$cmd = "[$utime] DISABLE_HOST_SVC_NOTIFICATIONS;$hostname";
nagios_send_command($cmd);
}

#---------------------------------------------------------------------------------

sub nagios_host_svc_enable {
my $hostname = shift;
my $full = shift || 0;
my $utime = timelocal(localtime());
my $cmd = "[$utime] ENABLE_HOST_SVC_CHECKS;$hostname";
nagios_send_command($cmd);
if ($full) {
    $cmd = "[$utime] ENABLE_ALL_NOTIFICATIONS_BEYOND_HOST;$hostname";
    nagios_send_command($cmd);
    }
$cmd = "[$utime] ENABLE_HOST_SVC_NOTIFICATIONS;$hostname";
nagios_send_command($cmd);
}

#---------------------------------------------------------------------------------

sub read_host_template {
my $device = shift;
my $template_file = shift;
my $result;
my @custom_cfg=();
if (-e $template_file) { @custom_cfg = read_file($template_file); } else { return; }
if (@custom_cfg and scalar(@custom_cfg)) {
    foreach my $row (@custom_cfg) {
	next if (!$row);
        $row=~s/\%HOSTNAME\%/$device->{name}/;
        $row=~s/\%HOST\%/$device->{name}/;
	$row=~s/\%HOSTIP\%/$device->{ip}/;
	$row=~s/\%HOST_IP\%/$device->{ip}/;
	$row=~s/\%COMMUNITY\%/$device->{community}/ if ($device->{community});
	$row=~s/\%RW_COMMUNITY\%/$device->{rw_community}/ if ($device->{rw_community});
	$row=~s/\%SNMP_VERSION\%/$device->{snmp_version}/ if ($device->{snmp_version});
	$row=~s/\%MODEL\%/$device->{device_model}->{model_name}/ if ($device->{device_model}->{model_name});
        push(@{$result->{template}},$row);
	if ($row=~/\s+service_description\s+(.*)$/i) { $result->{services}->{$1}=1; }
	}
    }
return $result;
}

sub print_single_host {
my $device = shift;
my $host_template = 'generic-host';
my $default_service="local-service";

my $ping_enable = $device->{ou}->{nagios_ping};
if ($device->{ou}->{nagios_host_use}) { $host_template=$device->{ou}->{nagios_host_use}; }
if ($device->{ou}->{nagios_default_service}) { $default_service=$device->{ou}->{nagios_default_service}; }

my $cfg_file = $device->{ou}->{nagios_dir}."/".$device->{name}.".cfg";
open(FH, "> $cfg_file");
print(FH "define host{\n");
print(FH "       use                     $host_template\n");
print(FH "       host_name               $device->{name}\n");
print(FH "       alias                   $device->{name}\n");
print(FH "       address                 $device->{ip}\n");
print(FH "       _ID			 $device->{auth_id}\n"); 
print(FH "       _TYPE			 user\n");
if ($device->{device_model}) {
	print(FH "       notes		$device->{device_model}->{model_name}\n"); 
	}
if ($device->{parent_name}) {
        print(FH "       parents                    $device->{parent_name}\n");
        }
print(FH "       notes_url       ".$config_ref{stat_url}."/admin/users/editauth.php?id=".$device->{auth_id}."\n");
print(FH "       }\n\n");

if ($ping_enable) {
	print(FH "define service{\n");
	print(FH "       use                    ping-service\n");
	print(FH "       host_name              $device->{name}\n");
	print(FH "       service_description    ping $device->{name}\n");
	print(FH "       check_command          check_ping_icmp!100.0,20%!500.0,60%\n");
	print(FH "       }\n");
	print(FH "\n");
    }
if ($device->{parent_name} and $device->{link_check} and $device->{parent_snmp_version}) {
	#port status
        print(FH "define service{\n");
        print(FH "       use                        $default_service\n");
        print(FH "       host_name                  $device->{parent_name}\n");
        print(FH "       service_description port $device->{parent_port} - $device->{name}\n");
        print(FH "       check_command              check_ifoperstatus!$device->{parent_port_snmp_index}!$device->{parent_community}\n");
        print(FH "       }\n");
        print(FH "\n");
        #crc
        print(FH "define service{\n");
        print(FH "       use                        service-snmp-crc\n");
        print(FH "       host_name                  $device->{parent_name}\n");
        print(FH "       service_description port $device->{parent_port} - $device->{name} CRC Errors\n");
        print(FH "       check_command              check_snmp_switch_crc!$device->{parent_community}!$device->{parent_port_snmp_index}\n");
        print(FH "       }\n\n");
    }
close(FH);
return $cfg_file;
}
#---------------------------------------------------------------------------------

sub print_nagios_cfg {

my $device = shift;
return if (!$device);
my $device_id = $device->{device_id};
my $custom_cfg;
my $device_custom_cfg = $config_ref{nagios_dir}."/custom-cfg/".$device->{name}.".cfg";
if (-e $device_custom_cfg) { $custom_cfg = read_host_template($device,$device_custom_cfg); }
$device_custom_cfg = $config_ref{nagios_dir}."/custom-cfg/".$device_id.".cfg";
if (-e $device_custom_cfg) { $custom_cfg = read_host_template($device,$device_custom_cfg); }
my $default_service="local-service";

if (!$device->{ou}->{nagios_dir}) { print Dumper($device); }

my $cfg_file = $device->{ou}->{nagios_dir}."/".$device->{name}.".cfg";

if ($custom_cfg->{template}) {
    open(FH, "> $cfg_file");
    my @custom_cfg = @{$custom_cfg->{template}};
    if (@custom_cfg and scalar(@custom_cfg)) {
	foreach my $row (@custom_cfg) {
	    next if (!$row);
            print(FH $row."\n");
	    }
	}
    close(FH);
    return;
    }

#switch | router
if ($device->{type} ~~ [1,2]) {
    open(FH, "> $cfg_file");
    my $device_template = 'switches';
    if ($device->{type} eq 2) {  $device_template='routers'; }
    print(FH "define  host {\n");
    print(FH "       use                     $device_template\n");
    print(FH "       host_name               $device->{name}\n");
    print(FH "       alias                   $device->{name}\n");
    print(FH "       address                 $device->{ip}\n");
    print(FH "       _ID                     $device->{device_id}\n");
    print(FH "       _TYPE                   device\n");
    if ($device->{device_model}) {
	print(FH "       notes		$device->{device_model}->{model_name}\n");
	}
    if ($device->{parent_name}) {
        print(FH "       parents                    $device->{parent_name}\n");
        }
    print(FH "       notes_url       ".$config_ref{stat_url}."/admin/devices/editdevice.php?id=$device->{device_id}\n");
    print(FH "       }\n\n");
    #ping
    print(FH "define service{\n");
    print(FH "        use                             ping-service         ; Name of service template to use\n");
    print(FH "        host_name                       $device->{name}\n");
    print(FH "        service_description             ping $device->{name}\n");
    print(FH "        check_command                   check_ping_icmp!100.0,20%!500.0,60%\n");
    print(FH "        }\n");
    #uptime
    if ($device->{snmp_version}) {
        print(FH "define service{\n");
	print(FH "        use                             $default_service\n");
        print(FH "        host_name                       $device->{name}\n");
	print(FH "        service_description             Uptime\n");
        print(FH "        check_command                   check_snmp_uptime!$device->{community}!161!$device->{snmp_version}\n");
	print(FH "        }\n");
        print(FH "\n");
        #uplink
        if (exists $device->{uplink}) {
	    print(FH "define service{\n");
    	    print(FH "       use                        service-snmp-crc\n");
            print(FH "       host_name                  $device->{name}\n");
            my $port_description = $device->{parent_name};
            my $conn = $device->{uplink};
            print(FH "       service_description port $conn->{port} - $port_description CRC Errors\n");
            print(FH "       check_command              check_snmp_switch_crc!$device->{community}!$conn->{snmp_index}\n");
            print(FH "       }\n\n");
    	    }
	foreach my $conn (@{$device->{downlinks}}) {
	    #id,port,snmp_index,comment
	    print(FH "define service{\n");
    	    print(FH "       use                        $default_service\n");
            print(FH "       host_name                  $device->{name}\n");
            my $port_description=translit($conn->{comment});
            if ($conn->{target_port_id}) { $port_description = $conn->{downlink_name}; }
            print(FH "       service_description port $conn->{port} - $port_description \n");
            print(FH "       check_command              check_ifoperstatus!$conn->{snmp_index}!$device->{community}\n");
            print(FH "       }\n\n");
            #src
	    print(FH "define service{\n");
    	    print(FH "       use                        service-snmp-crc\n");
            print(FH "       host_name                  $device->{name}\n");
            my $port_description=translit($conn->{comment});
            if ($conn->{target_port_id}) { $port_description = $conn->{downlink_name}; }
            print(FH "       service_description port $conn->{port} - $port_description CRC Errors\n");
            print(FH "       check_command              check_snmp_switch_crc!$device->{community}!$conn->{snmp_index}\n");
            print(FH "       }\n\n");
            #band
	    print(FH "define service{\n");
    	    print(FH "       use                        service-snmp-bandwidth\n");
            print(FH "       host_name                  $device->{name}\n");
            my $port_description=translit($conn->{comment});
            if ($conn->{target_port_id}) { $port_description = $conn->{downlink_name}; }
            print(FH "       service_description port $conn->{port} - $port_description bandwidth usage\n");
            print(FH "       check_command              check_snmp_bandwidth!$device->{community}!$conn->{snmp_index}\n");
            print(FH "       }\n\n");
	    }
	}
    close FH;
    }

#auth record
if ($device->{type} eq 3) {
    my $cfg_file = print_single_host($device);
    open(FH, ">> $cfg_file");
    my $dev_cfg;
    if ($device->{device_model} and $device->{device_model}->{nagios_template}) { $dev_cfg = read_host_template($device,$config_ref{nagios_dir}.'/gen_template/'.$device->{device_model}->{nagios_template}); }
    if ($dev_cfg and $dev_cfg->{template}) {
	    my @dev_cfg = @{$dev_cfg->{template}};
	    if (@dev_cfg and scalar(@dev_cfg)) {
		foreach my $row (@dev_cfg) {
		    next if (!$row);
    		    print(FH $row."\n");
		    }
		}
        }
    close FH;
    }
}

#---------------------------------------------------------------------------------

1;
}
