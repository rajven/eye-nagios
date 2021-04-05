#! /usr/bin/perl -w

use strict;
use Net::SNMP;
use Data::Dumper;

my $hostip=$ARGV[0];

my ($session, $error) = Net::SNMP->session(
    -hostname  => shift || $hostip,
    -community => shift || 'public',
    -port      => shift || 161,
    -version   => shift || 2
);

if (!defined($session)) {
    printf("ERROR: %s.\n", $error);
    exit 1;
}
my @resmessage = ("Battery OK","Battery discharged","Battery low level"," ","Battery is off","notFunctioning(6)","The battery is charging");
my $batpower = '1.3.6.1.4.1.89.53.15.1.3.1';
my $result = $session->get_request(
    -varbindlist => [$batpower]
);

if (!defined($result)) {
    printf("ERROR: %s.\n", $session->error);
    $session->close;
    exit 2;
}
#print Dumper($result);
my $v=$result->{$batpower};
if (($v == 1) or ($v == 5) or ($v == 7)) {
#    print("Battery OK! $v\n");
	printf("%s.\n",$resmessage[$v-1]);
	$session->close;
	exit 0;
} else {
    if ($v == 2) {
#	print("WARNING ! $v\n");
	printf("WARNING ! %s.\n",$resmessage[$v-1]);
	$session->close;
	exit 1;
    } else {
#	print("ERROR ! $v\n");
	printf("ERROR ! %s.\n",$resmessage[$v-1]);
	$session->close;
	exit 2;
    }
}
