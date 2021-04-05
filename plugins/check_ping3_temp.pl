#! /usr/bin/perl -w

use strict;
use Net::SNMP;

my $hostip = shift;
my $index = shift || '1';

exit if (!$hostip);

my ($session, $error) = Net::SNMP->session(
    -hostname  => $hostip,
    -community => shift || 'public',
    -port      => shift || 161,
    -version   => '2'
);

if (!defined($session)) {  printf("ERROR: %s.\n", $error);  exit 1; }

my $sensor_names = '.1.3.6.1.4.1.35160.1.16.1.2.'.$index;
my $sensor_values = '.1.3.6.1.4.1.35160.1.16.1.13.'.$index;

my $sensor_list = $session->get_request( -varbindlist=>[$sensor_names]);
if (!defined($sensor_list)) {
    printf("ERROR: %s.\n", $session->error);
    $session->close;
    exit 2;
}

my $sensor_name=$sensor_list->{$sensor_names};

my $result = $session->get_request( -varbindlist=>[$sensor_values]);
if (!defined($result)) {
    printf("ERROR: %s.\n", $session->error);
    $session->close;
    exit 2;
}

my $temp_value=$result->{$sensor_values}/10;

my $perf="temp=%s;50;60;-50;100;";

if ($temp_value >60) {
    printf("CRIT: Fire!!! SENS [$sensor_name] Temperature $temp_value C|".$perf."\n",$temp_value);
    exit 2;
    }
if ($temp_value >50) {
    printf("WARN: I'm not hotdog!!! SENS [$sensor_name] Temperature $temp_value C|".$perf."\n",$temp_value);
    exit 1;
    }
if ($temp_value <=1) {
    printf("CRIT: I'm frozen! SENS [$sensor_name] Temperature $temp_value C|".$perf."\n",$temp_value);
    exit 2;
    }

printf("OK: SENS [$sensor_name] Temperature $temp_value C|".$perf."\n",$temp_value);
exit 0;
