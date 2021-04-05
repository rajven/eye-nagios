#!/usr/bin/perl -w

# Author: Martin Fuerstenau, Oce Printing Systems
#         martin.fuerstenau_at_oce.com or Martin.fuerstenau_at_nagiossw.org
#
# Date:   14 Apr 2011
# 
#
# Purpose and features of the program:
#
# - Get the CPU Usage for Windows, Solaris and Linux servers.
#

use strict;
use Getopt::Long;
use File::Basename;

#--- Start presets and declarations ----------------------------------------------

my $version = '1.0';             # The program version
my $get_version;                 # Switch to display the program version
my $progname = basename($0);     # The name of the program
my $warning;                     # The warning threshold
my $warning_def=80;              # The default warning threshold
my $critical;                    # The critical threshold
my $critical_def=90;             # The default critical threshold
my $result;                      # The result from the snmpwalk
my @result;                      # The splitted result from the snmpwalk
my $host;                        # Host to check
my $help;                        # Switch to display the help function
my $community;                   # Contains the SNMP community string
my $community_def="public";      # Contains the SNMP default community string
my $NoA;                         # Number of Arguments handled over to the program
                                 # -1 means no arguments which will cause an error
my $cpu_usage="";                # The usage per CPU
my $avg_usage;                   # The usage for all CPUs
my $perf_usage;                  # The usage for all 
my $noperfdata;                  # If set no performance data will be delivered
my $NoC;                         # Number of CPUs
my $snmpversion;                 # SNMP version
my $snmpversion_def=1;           # SNMP version default
my $timeout;                     # SNMP timeout
my $timeout_def=60;              # SNMP timeout default

sub usage();
sub help ();

#--- End presets -----------------------------------------------------------------

# First we have to fix  the number of arguments

$NoA=$#ARGV;

Getopt::Long::Configure('bundling');
GetOptions
	("H=s" => \$host,         "hostname=s"    => \$host,
         "C=s" => \$community,    "community=s"   => \$community,
	 "w=s" => \$warning,      "warning=s"     => \$warning,
	 "c=s" => \$critical,     "critical=s"    => \$critical,
	 "t=s" => \$timeout,      "timeout=s"     => \$timeout,
	 "V"   => \$get_version,  "version"       => \$get_version,
	 "v=s" => \$snmpversion,  "snmpversion=s" => \$snmpversion,
	 "n"   => \$noperfdata,   "noperfdata"    => \$noperfdata,
         "h"   => \$help,         "help"          => \$help);


if ($get_version)
   {
   print "$progname version: $version\n";
   exit 0;
   }

if ($help)
   {
   help();
   exit 0;
   }

# Right number of arguments (therefore noa :-)) )

if ( $NoA == -1 )
   {
   usage();
   exit 1;
   }

if (!$warning)
   {
   $warning=$warning_def;
   }

if (!$critical)
   {
   $critical=$critical_def;
   }

if (!$timeout)
   {
   $timeout=$timeout_def;
   }

if (!$host)
   {
   print "Host name/address not specified\n\n";
   usage();
   exit 1;
   }

if (!$snmpversion)
   {
   $snmpversion=$snmpversion_def;
   }
else   
   {
   if ( $snmpversion ne "1" )
      {
      if ( $snmpversion ne "2c" )
         {
         print "\nWrong SNMP version submitted. Only version 1 of 2c is allowed.\n\n";
         exit 1;
         }
      }
   }

if (!$community)
   {
   $community = $community_def;
   print "No community string supplied - using default $community_def\n";
   }

$result =`snmpwalk -v $snmpversion -t $timeout -c $community $host 1.3.6.1.2.1.25.3.3.1.2`;

if ( $result )
   {
   @result = split (/\n/,$result);
   $NoC=0;
  
   foreach ( @result )
           {
           s/HOST-RESOURCES-MIB::hrProcessorLoad.\d+ = INTEGER://g;	
           $avg_usage+=$_;
           $cpu_usage=$cpu_usage.", CPU-$NoC:$_%".";".$warning.";".$critical;
           $NoC++;
           }
   $avg_usage = $avg_usage / $NoC;
   $avg_usage = sprintf("%.0f",$avg_usage);
   $perf_usage = $cpu_usage;
   $cpu_usage =~ s/;$warning;$critical//g;
   $perf_usage =~ s/, / /g;
   $perf_usage =~ s/: /=/g;
   $perf_usage = "CPU-AVG=".$avg_usage."%".";".$warning.";".$critical.$perf_usage;

   if ( $avg_usage < $warning )
      {
      if (!$noperfdata)
         {
         print "OK: Average CPU usage: $avg_usage%$cpu_usage|$perf_usage";
         exit 0;
         }
      else
         {
         print "OK: Average CPU usage: $avg_usage%$cpu_usage";
         exit 0;
         }
      }
   else
      {
      if ( $avg_usage >= $warning )
         {
         if ( $avg_usage < $critical )
            {
            if (!$noperfdata)
               {
               print "WARNING: Average CPU usage: $avg_usage%$cpu_usage|$perf_usage";
               exit 1;
               }
            else
               {
               print "WARNING: Average CPU usage: $avg_usage%$cpu_usage";
               exit 1;
               }
            }
         else
            {
            if (!$noperfdata)
               {
               print "CRITICAL: Average CPU usage: $avg_usage%$cpu_usage|$perf_usage";
               exit 2;
               }
            else
               {
               print "CRITICAL: Average CPU usage: $avg_usage%$cpu_usage";
               exit 2;
               }
            }
         }
      }
   }
else
   {
   print "Unknown: No response\n";
   exit 3;
   }


# ---- Subroutines -------------------------------------------------------

sub usage()
    {
    print "Usage:\n";
    print "$progname -H <host>|--hostname=<host> [-C <community>|--community=<community>] ";
    print "[-v <1|2c>|--snmpversion=<1|2c>] [-t <timeout>|--timeout=<timeout>] [-n|--noperfdata] ";
    print "[-w <threshold>|--warning=<threshold>] [-c <threshold>|--critical=<threshold>]\n\n";
    print "or \n\n";
    print "$progname -h|--help\n\n";
    print "or \n\n";
    print "$progname -V|--version\n";
    }

sub help ()
    {
    usage();

    print "This plugin check the CPU usage of solaris, linux and windows servers\n\n";

    print "-h|--help                               Print detailed help screen\n";
    print "-V|--version                            Print version information\n";
    print "-H <host>|--hostname=<host>             Hostname/IP-Adress to use for the check.\n";
    print "-C <community>|--community=<community>  SNMP community that should be used to access the switch.\n";
    print "                                        Default: $community_def\n";
    print "-n|--noperfdata                         Don't print performance data.\n";
    print "-t <timeout>|--timeout=<timeout>        Seconds before plugin times out.\n";
    print "                                        Default: $timeout_def\n";
    print "-v <1|2c>|--snmpversion=<1|2c>          SNMP version details for command-line debugging (can repeat up to 3 times)\n\n";
    print "                                        Default: $snmpversion_def\n";
    print "-w <threshold>|--warning=<threshold>    Warning threshold in percent.\n\n";
    print "                                        Default: $warning_def\n";
    print "-c <threshold>|--critical=<threshold>   Critical threshold in percent.\n\n";
    print "                                        Default: $critical_def\n";
    }
