#!/usr/bin/perl -w

use Data::Dumper;
use Net::SNMP;
use strict;

### return codes
my $RET_OK=0;
my $RET_WARNING=1;
my $RET_UNKNOWN=3;
my $RET_CRITICAL=2;

my $version = "v2c";

if (scalar @ARGV <= 2) {
    print "Usage: checksnmp_mac_ext.pl <hostname> <community> <port> <min_count> <max_count> <vlan>\n";
    exit $RET_UNKNOWN;
    }

my $host = shift @ARGV;
my $community = shift @ARGV;
my $port = shift @ARGV;
my $min_count = shift @ARGV || '1';
my $max_count = shift @ARGV || '1000';
my $vlan = shift @ARGV;

my $MAC_OID = "1.3.6.1.2.1.17.7.1.2.2.1.2";
if ($vlan) { $MAC_OID="$MAC_OID.$vlan"; }

my ($session, $error) = Net::SNMP->session(
         -hostname	=> $host,
         -version	=> $version,
         -timeout	=> 15,
         -community	=> $community
      );

if (!defined($session)) {
    printf("ERROR: %s.\n", $error);
    exit $RET_UNKNOWN;
    }

my $result = $session->get_table($MAC_OID);
$session->close;

my $mac_count = 0;
foreach my $row (keys (%$result)) {
next if ($row !~ /$MAC_OID/);
next if ($result->{$row} ne $port);
$mac_count++;
}

my $perf="Count=%s;0;0;0;10000;";

if ($mac_count >= $min_count) {
    if ($mac_count > $max_count) {
        printf("CRIT: Mac count: ".$mac_count." is overlimit!|".$perf."\n",$mac_count);
	exit $RET_CRITICAL;
	}
    printf("OK: Mac count: ".$mac_count." |".$perf."\n",$mac_count);
    exit $RET_OK;
    } else {
    printf("CRIT: No mac at port! |".$perf."\n",$mac_count);
    exit $RET_CRITICAL;
    }

printf("OK: Mac count: ".$mac_count." |".$perf."\n",$mac_count);
exit $RET_OK;
