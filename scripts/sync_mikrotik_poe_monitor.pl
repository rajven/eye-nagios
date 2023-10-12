#!/usr/bin/perl -w

#
# Copyright (C) Roman Dmitiriev, rnd@rajven.ru
#

use FindBin '$Bin';
use lib "$Bin/";
use strict;
use Time::Local;
use FileHandle;
use Data::Dumper;
use eyelib::config;
use eyelib::main;
use eyelib::cmd;
use Net::Patricia;
use Date::Parse;
use eyelib::net_utils;
use eyelib::mysql;
use DBI;
use utf8;
use Fcntl qw(:flock);

open(SELF,"<",$0) or die "Cannot open $0 - $!";
flock(SELF, LOCK_EX|LOCK_NB) or exit 1;

#exit;
#$debug = 1;

$|=1;

if (IsNotRun($SPID)) { Add_PID($SPID); }  else { die "Warning!!! $SPID already runnning!\n"; }

my @poe_mikrotik = get_records_sql($dbh,"SELECT * FROM devices WHERE deleted=0 and device_model_id=12");

foreach my $device (@poe_mikrotik) {
next if (!$device);
my $switch_name=$device->{device_name};
my $switch_ip=$device->{ip};

my @cmd_list=();

my @auth_list = get_records_sql($dbh,"SELECT DP.port,AU.ip FROM `device_ports` AS DP, `User_auth` as AU, `connections` as C WHERE DP.id=C.port_id and C.auth_id=AU.id and AU.deleted=0 and AU.link_check=1 and AU.nagios=1 and C.device_id=".$device->{id}."");

my %work_list;
foreach my $auth (@auth_list) {
next if (!$auth);
$work_list{'ether'.$auth->{port}}=$auth->{ip};
}

$device = netdev_set_auth($device);
$device->{login}.='+ct400w';

db_log_verbose($dbh,"Sync link monitor at $switch_name [".$switch_ip."] started.");

my $t = netdev_login($device);

#/interface ethernet terse
#/interface ethernet set [ find default-name=ether1 ] loop-protect=on power-cycle-ping-address=192.168.22.51 power-cycle-ping-enabled=yes power-cycle-ping-timeout=3m speed=100Mbps
#/interface ethernet set [ find default-name=ether2 ] loop-protect=on speed=100Mbps

#fetch current
my @current_monitor=netdev_cmd($device,$t,'ssh','/interface ethernet export terse',1);
@current_monitor=grep(/power/,@current_monitor);

my %current_list;
foreach my $poe (@current_monitor) {
next if (!$poe);
my $port_name;
my $ping_enabled=0;
my $ping_address;
my @words=split(/ /,$poe);
    foreach my $item (@words) {
    if ($item=~/(ether\d{1,2})/) { $port_name=$1; }
    if ($item=~/power-cycle-ping-address=(.*)/) { $ping_address=$1; }
    if ($item=~/power-cycle-ping-enabled=yes/) { $ping_enabled=1; }
    }
next if (!$ping_enabled);
next if (!$port_name or !$ping_address);
$current_list{$port_name}=$ping_address;
}

foreach my $current_port (keys %current_list) {
if (defined $work_list{$current_port}) {
    if ($work_list{$current_port} ne $current_list{$current_port}) {
        db_log_info($dbh,"Change settings poe monitor at $switch_name [$current_port] to ip: $work_list{$current_port}");
	push(@cmd_list,'/interface ethernet set [ find default-name='.$current_port.' ] power-cycle-ping-address='.$work_list{$current_port}.' power-cycle-ping-enabled=yes power-cycle-ping-timeout=3m'); 
	}
    } else {
    db_log_info($dbh,"Disable poe monitor at $switch_name [$current_port]");
    push(@cmd_list,'/interface ethernet set [ find default-name='.$current_port.' ] power-cycle-ping-enabled=no');
    }
}

foreach my $work_port (keys %work_list) {
if (!defined $current_list{$work_port}) {
    db_log_info($dbh,"Enable poe monitor at $switch_name [$work_port] for $work_list{$work_port}");
    push(@cmd_list,'/interface ethernet set [ find default-name='.$work_port.' ] power-cycle-ping-address='.$work_list{$work_port}.' power-cycle-ping-enabled=yes power-cycle-ping-timeout=3m');
    }
}

if (scalar(@cmd_list)) {
    netdev_cmd($device,$t,'ssh',\@cmd_list,1);
    if ($debug) { foreach my $cmd (@cmd_list) { db_log_debug($dbh,"$cmd"); } }
    }

db_log_verbose($dbh,"Sync link monitor at $switch_name [".$switch_ip."] stopped.");
}

$dbh->disconnect();

if (IsMyPID($SPID)) { Remove_PID($SPID); };

do_exit 0;
