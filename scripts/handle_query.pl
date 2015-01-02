#!/usr/bin/perl

use Bib::CrossRef;
use Bib::Tools;
use CGI;

# send html header
print "Content-Type: text/html;\n\n";

my $q = CGI->new;
my $refs = Bib::Tools->new;
my $orcid = scalar $q->param('orcid');
$orcid =~ /([0-9\-]+)$/; # extract id out of url
$orcid = $1;
if (length($orcid) > 5) {
  $refs->add_orcid($1);
} 

my $google = scalar $q->param('google'); #NB: CGI has already carried out URL decoding
# TO DO: validate. 
if (length($google) > 5) {
  if (!($google =~ m/^http/)) { $google = "http://".$google;}
  $refs->add_google($google);
}
my $google2 = scalar $q->param('google2'); #NB: CGI has already carried out URL decoding
# TO DO: validate
if (length($google2) > 5) {
  if (!($google2 =~ m/^http/)) { $google2 = "http://".$google2;}
  $refs->add_google_search($google2);
}
my @values = $q->multi_param('refs');
foreach my $value (@values) {
  #NB: CGI has already carried out URL decoding
  open my $fh, "<", \$value;
  $refs->add_fromfile($fh);
}      
print $refs->send_resp;
