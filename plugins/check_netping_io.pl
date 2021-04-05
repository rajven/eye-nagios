#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use Net::SNMP;

my $netping_oids = {
'netpingIOlevel'=>'.1.3.6.1.4.1.25728.8900.1.1.2',
'netpingIOLineName'=>'.1.3.6.1.4.1.25728.8900.1.1.6',
'netpingIOCount'=>'.1.3.6.1.4.1.25728.8900.1.1.9'
};

exit if (!$ARGV[0]);

my $hostip=$ARGV[0];

my $line =$ARGV[1] || '1';

my $community = $ARGV[2] || 'public';

my $location_oid = '.1.3.6.1.2.1.1.6.0';

my ($session, $error) = Net::SNMP->session(
   -hostname  => shift || $hostip,
   -version   => shift || 2,
   -community => shift || $community,
   -port      => shift || 161 
);

if (!defined($session)) {
   printf("ERROR: %s.\n", $error);
   exit 1;
}

my $line_oid = $netping_oids->{netpingIOlevel}.'.'.$line;
my $desc_oid = $netping_oids->{netpingIOLineName}.'.'.$line;

my $result = $session->get_request( -varbindlist => [$line_oid] );
my $status = $result->{$line_oid};

$result = $session->get_request( -varbindlist => [$desc_oid] );
my $desc = $result->{$desc_oid};

$result = $session->get_request( -varbindlist => [$location_oid] );
my $location = $result->{$location_oid};
$session->close;

if ($status) {
   print("CRIT: $location $desc detected!\n");
   exit 2;
}

print("OK: $location $desc\n");
exit 0;
