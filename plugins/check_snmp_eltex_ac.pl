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

my $acpower = '1.3.6.1.4.1.89.53.15.1.2.1';
my $result = $session->get_request(
    -varbindlist => [$acpower]
);

if (!defined($result)) {
    printf("ERROR: %s.\n", $session->error);
    $session->close;
    exit 2;
}
#print Dumper($result);
my $v=$result->{$acpower};
if ($v == 1) {
    print("AC Power OK!\n");
	$session->close;
	exit 0;
} else {
    print("ERROR AC Power!\n");
    $session->close;
    exit 2;
}
