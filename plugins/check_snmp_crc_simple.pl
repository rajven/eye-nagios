#!/usr/bin/perl -w

use Data::Dumper;
use Net::SNMP;
use Config::Tiny;
use File::Path qw( mkpath );
use strict;

### return codes
my $RET_OK=0;
my $RET_WARNING=1;
my $RET_UNKNOWN=3;
my $RET_CRITICAL=2;

my $version = "v2c";

my $time_cache = 1800;

my $err_step = 100;

if (scalar @ARGV <= 2) {
    print "Usage: check_snmp_crc_simple.pl <host> <community> <port>\n";
    exit $RET_OK;
    }

my $host = shift @ARGV;
my $community = shift @ARGV;
my $port = shift @ARGV;

sub get_snmp_crc {
my $host = shift;
my $community = shift;
my $port = shift;
my $CRC_OID = ".1.3.6.1.2.1.2.2.1.14.".$port;
my ($session, $error) = Net::SNMP->session(
         -hostname	=> $host,
         -version	=> '2c',
         -timeout	=> 15,
         -community	=> $community
      );
if (!defined($session)) {
    printf("ERROR: %s.\n", $error);
    exit $RET_OK;
    }
my $result = $session->get_request( -varbindlist => [$CRC_OID]);
$session->close;
my %port_crc;
$port_crc{$port} = $result->{$CRC_OID};
return \%port_crc;
}

my $time_cache_min = int($time_cache/60);

my $start_time = time();
my $host_spool_dir = "/var/spool/nagios/plugins/crc/".$host;

if (!-e "$host_spool_dir") { mkpath( $host_spool_dir, 0, 0770 ); }

my $host_data = $host_spool_dir.'/'.$host."-port-".$port;

my $old_crc_info;
my $cur_crc_info;

my $need_rescan = 0;

if (-e "$host_data") {
    my $host_spool = Config::Tiny->new;
    $host_spool = Config::Tiny->read($host_data, 'utf8' );
    my $old_time=$host_spool->{_}->{timestamp};
    foreach my $port (keys %{$host_spool->{crc_data}}) { $old_crc_info->{$port} = $host_spool->{crc_data}->{$port}; }
    if (($start_time - $old_time) >=$time_cache) { $need_rescan = 1; } else { $need_rescan = 0; }
    } else { $need_rescan = 1; }

if (!$old_crc_info->{$port}) { $old_crc_info->{$port}=0; }

if ($need_rescan) {
    $cur_crc_info=get_snmp_crc($host,$community,$port);
    my $host_spool = Config::Tiny->new;
    $host_spool->{_}->{timestamp}=$start_time;
    $host_spool->{crc_data} = $cur_crc_info;
    $host_spool->write($host_data);
    } else { $cur_crc_info = $old_crc_info; }

my $diff_crc = $cur_crc_info->{$port} - $old_crc_info->{$port};

my $perf="ErrSpeed=%s;0;0;0;10000000;";

if ($diff_crc >0 and $diff_crc >= $err_step) {
    my $speed_crc = int($diff_crc/$time_cache_min);
    printf("CRIT: CRC error found! Speedup $speed_crc by minute!|".$perf."\n",$speed_crc);
    exit $RET_CRITICAL;
    }

printf("OK: Errors not found. |".$perf."\n",0);

exit $RET_OK;
