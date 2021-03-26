package Rstat::nagios;

#use v5.28;
use utf8;
use open ":encoding(utf8)";

use strict;
use English;
use FindBin '$Bin';
use lib "$Bin";
use base 'Exporter';
use vars qw(@EXPORT @ISA);
use Rstat::config;
use Rstat::main;
use Rstat::mfi;
use Time::Local;
use Data::Dumper;

@ISA = qw(Exporter);
@EXPORT = qw(
$nag_cmd
nagios_send_command
nagios_host_svc_disable
nagios_host_svc_enable
print_nagios_cfg
);

BEGIN
{

our $nag_cmd = "/var/spool/nagios/cmd/nagios.cmd";

#---------------------------------------------------------------------------------

sub nagios_send_command {
my $command = shift;
next if (!$command);
if (!-e $nag_cmd) { die("Command socket $nag_cmd not found!"); }
log_info("Send command: $command to $nag_cmd");
open(FH, ">> $nag_cmd");
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
if (-e $template_file) { @custom_cfg = read_file($template_file);  }
if (@custom_cfg and scalar(@custom_cfg)) {
    foreach my $row (@custom_cfg) {
	next if (!$row);
        $row=~s/\%HOSTNAME\%/$device->{name}/;
        $row=~s/\%HOST\%/$device->{name}/;
	$row=~s/\%HOSTIP\%/$device->{ip}/;
        push(@{$result->{template}},$row);
	if ($row=~/\s+service_description\s+(.*)$/i) { $result->{services}->{$1}=1; }
	}
    }
return $result;
}

sub print_single_host {
my $device = shift;
my $ping_enable = shift || 0;
my $group = 'any';
my $template = 'generic-host';

my $default_service="local-service";

if ($device->{ou_id} ~~ [4,5,6,8,9,12]) {
    #12 - WiFi AP
    if ($device->{ou_id} eq 12 ) { $group = 'ap'; $template='ap'; }
    #4 - VOIP
    if ($device->{ou_id} eq 4 ) { $group = 'voip'; $template='voip'; }
    #5 - IPCAM
    if ($device->{ou_id} eq 5 ) { $group = 'videocam'; $template='ip-cam'; }
    #6 - Printers
    if ($device->{ou_id} eq 6 ) { $group = 'printers'; $template='printers'; $default_service='printer-service'; }
    #8 - UPS
    if ($device->{ou_id} eq 8 ) { $group = 'ups'; $template='ups'; }
    #9 - Охрана
    if ($device->{ou_id} eq 9 ) { $group = 'security'; $template='security'; }
    }

my $cfg_file = "/etc/nagios/".$group."/".$device->{name}.".cfg";
open(FH, "> $cfg_file");
print(FH "define host{\n");
print(FH "       use                     $template\n");
print(FH "       host_name               $device->{name}\n");
print(FH "       alias                   $device->{name}\n");
print(FH "       address                 $device->{ip}\n");
print(FH "       _ID			 $device->{auth_id}\n"); 
print(FH "       _TYPE			 user\n"); 
if ($device->{device_model}) {
	print(FH "       notes		$device->{device_model}\n"); 
	}
if ($device->{parent_name}) {
        print(FH "       parents                    $device->{parent_name}\n");
        }
print(FH "       notes_url       http://stat.lan.local/admin/users/editauth.php?id=$device->{auth_id}\n");
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
        print(FH "define service{\n");
        print(FH "       use                        $default_service\n");
        print(FH "       host_name                  $device->{parent_name}\n");
        print(FH "       service_description port $device->{parent_port} - $device->{name}\n");
        print(FH "       check_command              check_ifoperstatus!$device->{parent_port_snmp_index}!$device->{parent_community}\n");
        print(FH "       }\n");
        print(FH "\n");
        #src
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
my $device_custom_cfg = "/etc/nagios/custom-cfg/".$device->{name}.".cfg";
if (-e $device_custom_cfg) { $custom_cfg = read_host_template($device,$device_custom_cfg); }
$device_custom_cfg = "/etc/nagios/custom-cfg/".$device_id.".cfg";
if (-e $device_custom_cfg) { $custom_cfg = read_host_template($device,$device_custom_cfg); }

my $default_service="local-service";

#switch | router
if ($device->{type} ~~ [1,2]) {
    my $cfg_file = "/etc/nagios/switches/".$device->{name}.".cfg";
    my $device_template = 'switches';
    if ($device->{type} eq 1) {  $cfg_file = "/etc/nagios/routers/".$device->{name}.".cfg"; $device_template='routers'; }
    open(FH, "> $cfg_file");
    print(FH "define  host {\n");
    print(FH "       use                     $device_template\n");
    print(FH "       host_name               $device->{name}\n");
    print(FH "       alias                   $device->{name}\n");
    print(FH "       address                 $device->{ip}\n");
    print(FH "       _ID                 $device->{device_id}\n");
    print(FH "       _TYPE                 device\n");
    if ($device->{device_model}) {
	print(FH "       notes		$device->{device_model}\n"); 
	}
    if ($device->{parent_name}) {
        print(FH "       parents                    $device->{parent_name}\n");
        }
    print(FH "       notes_url       http://stat.lan.local/admin/devices/editswitches.php?id=$device->{device_id}\n");
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
    }
#auth record
if ($device->{type} eq 3) {
    my $add_ping = 1;
    if ($device->{ou_id} ~~ [5,22,23,24]) { $add_ping = 0; }
    my $cfg_file = print_single_host($device,$add_ping);
    open(FH, ">> $cfg_file");
    #IPCAM
    if ($device->{ou_id} eq 5) {
        print(FH "define service {\n");
	print(FH "       use                     $default_service\n");
        print(FH "       host_name               $device->{name}\n");
	print(FH "       service_description     Snmp Model\n");
        print(FH "       contact_groups          admins\n");
	print(FH "       check_command           check_snmp_hikvision\n");
        print(FH "       }\n");
	print(FH "\n");
	}
    #Printers
    if ($device->{ou_id} eq 6) {
	my $printer_cfg;
	if ($device->{device_model}=~/^OKI\s+/i) { $printer_cfg = read_host_template($device,'/etc/nagios/gen_template/oki.cfg'); }
	if ($device->{device_model}=~/^HP\s+/i) { $printer_cfg = read_host_template($device,'/etc/nagios/gen_template/hp.cfg'); }
	if ($device->{device_model}=~/^Panasonic\s+/i) { $printer_cfg = read_host_template($device,'/etc/nagios/gen_template/panasonic.cfg'); }
	if ($device->{device_model}=~/^Epson\s+/i) { $printer_cfg = read_host_template($device,'/etc/nagios/gen_template/epson.cfg'); }
	if ($printer_cfg->{template}) {
	    my @printer_cfg = @{$printer_cfg->{template}};
	    if (@printer_cfg and scalar(@printer_cfg)) {
		foreach my $row (@printer_cfg) {
		    next if (!$row);
    		    print(FH $row."\n");
		    }
		}
	    }
	}
    # UPS
    if ($device->{ou_id} eq 8) {
	my $ups_cfg = read_host_template($device,'/etc/nagios/gen_template/ups.cfg');
	if ($ups_cfg->{template}) {
	    my @ups_cfg = @{$ups_cfg->{template}};
	    if (@ups_cfg and scalar(@ups_cfg)) {
		foreach my $row (@ups_cfg) {
		    next if (!$row);
    		    print(FH $row."\n");
		    }
		}
	    }
	}
    }

if ($custom_cfg->{template}) {
    my @custom_cfg = @{$custom_cfg->{template}};
    if (@custom_cfg and scalar(@custom_cfg)) {
	foreach my $row (@custom_cfg) {
	    next if (!$row);
            print(FH $row."\n");
	    }
	}
    }
close(FH);
}

#---------------------------------------------------------------------------------

1;
}
