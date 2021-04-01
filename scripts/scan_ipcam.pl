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
use Net::SNMP qw(ticks_to_time TRANSLATE_NONE);
use Rstat::config;
use Rstat::main;
use Rstat::mysql;

my %hik_snmp_oids=(
'.1.3.6.1.4.1.39165.1.1.0'=>'Model',
'.1.3.6.1.4.1.39165.1.3.0'=>'Firmware',
'.1.3.6.1.4.1.39165.1.5.0'=>'Number',
'.1.3.6.1.4.1.39165.1.6.0'=>'Vendor',
);

my @hik_oids=();
foreach my $oid (keys %hik_snmp_oids) {
push (@hik_oids,$oid);
}

sub scan_ipcam {

my $ip = shift;
my $community = shift;
my $result;

eval {
my ($session, $error) = Net::SNMP->session(
   -hostname  => $ip,
   -community => $community,
   -port      => 161,
   -version   => '2'
);

$session->translate(TRANSLATE_NONE);
my $ret = $session->get_request( -varbindlist => [@hik_oids] );
$result->{text} = 'ip: '.$ip;
foreach my $oid (keys %hik_snmp_oids) {
    $result->{text} = $result->{text}." ".$hik_snmp_oids{$oid}.": ".$ret->{$oid};
    if ($hik_snmp_oids{$oid}=~/Model/i) { $result->{model_name}=$ret->{$oid}; }
    }
$result->{text} = trim($result->{text});
};

return $result;
}

my @auth_list=get_records_sql($dbh,'SELECT * FROM User_auth WHERE deleted=0 and nagios=1');

##################################### User auth analyze ################################################

if (scalar(@auth_list)>0) {
    foreach my $auth (@auth_list) {
        next if (!$auth);
        my $ip = $auth->{'ip'};
        $ip =~s/\/\d+$//g;
        $devices{$device_id}{ip}=$ip;
        #get user
        my $login = get_record_sql($dbh,"SELECT * FROM User_list WHERE id=".$auth->{'user_id'});
        next if ($login->{ou_id} ne 5);
        $devices{$device_id}{device_model} = $auth->{'host_model'};
        $devices{$device_id}{dns_name} = $auth->{'dns_name'};
        $devices{$device_id}{auth_id} = $auth->{'id'};
	my $snmp_info = scan_ipcam($auth->{ip},$config_ref{snmp_default_community});
	if ($snmp_info->{model_name}) {
	    print $snmp_info->{text}."\n";
	    my $model = get_record_sql($dbh,"SELECT id FROM device_models WHERE model_name='".$snmp_info->{model_name}."'");
	    if ($model) {
	        do_sql($dbh,"UPDATE User_auth SET device_model_id=".$model->{id}." WHERE id=".$auth->{'id'});
	        }
            }
        }
    }

exit;