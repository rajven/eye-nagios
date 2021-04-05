#!/usr/bin/perl 
# -wT

##################################################
#  proxy checker for netsaint                    #
#  - squid and other http proxy                  #
#------------------------------------------------#
#  check_prox <tested-url> <proxy-url>           #
#     [-l login] [-p password]                   #
#                                                #
#================================================#
#  IK. 11.05.2000                                #
##################################################                  

### NOTES
#

### TODO 
#

### CHANGELOG
#

### libraries
use LWP::UserAgent;
use HTTP::Headers;

### files 
my $PING_COMMAND="/bin/ping -q";

### return codes
my $RET_OK=0;
my $RET_WARNING=1;
my $RET_UNKNOWN=-1;
my $RET_CRITICAL=2;


# defaults
my $proxy_login="";
my $proxy_password="";


### read arguments
if ($#ARGV < 1) { die "Error: incorrect arguments"};
my $site_url=shift @ARGV;
my $proxy_url=shift @ARGV;

while (my $ARG = shift @ARGV){
    if ($ARG =~ /-p/i) {
	$proxy_password = shift @ARGV;
	next;
    }
    if ($ARG =~ /-l/i) {
	$proxy_login = shift @ARGV;
	next;
    }    
}

### make connections
# user agent
my $ua = new LWP::UserAgent;
#$ua->agent("test-url " . $ua->agent);
$ua->timeout(20);

# make request without proxy
my $req = new HTTP::Request('GET',$site_url);
#print "$site_url\n";

#simple_res = ($ua->request($req))->is_success;

my $res = $ua->request($req);
my $simple_res = $res->is_success;

if (! $simple_res) {
    print "Site URL is not available directly";
    exit $RET_UNKNOWN
}

# print "$simple_res\n";


# make proxy request
my $start_time=time;
$ua->proxy(http  => $proxy_url);
if ($proxy_login ne "") {
    $req->proxy_authorization_basic($proxy_login, $proxy_password);    
}
my $proxy_res = ($ua->request($req))->is_success;
my $stop_time=time;
# print "$proxy_res\n";

if (! $proxy_res) {
    print "Proxy is down";
    exit $RET_CRITICAL
};

my $connect_time=$stop_time-$start_time;
print "proxy delay = $connect_time";
exit $RET_OK;
