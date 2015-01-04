############################################################
#
#   Bib::Tools - For managing collections of Bib::CrossRef references.
#
############################################################

package Bib::Tools;

use 5.8.8;
use strict;
use warnings;
no warnings 'uninitialized';

require Exporter;
use Bib::CrossRef;
use LWP::UserAgent;
use JSON qw/decode_json/;
use URI::Escape qw(uri_escape_utf8 uri_unescape);
use HTML::Entities qw(decode_entities encode_entities);
use HTML::TreeBuilder::XPath;
use XML::Simple qw(XMLin);
use BibTeX::Parser qw(new next);
use IO::File;
#use Data::Dumper;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS @ISA);

#use LWP::Protocol::https;
use Data::Dumper;

$VERSION = '0.09';
@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(
sethtml clearhtml add_details add_google add_google_search add_orcid add_fromfile add_dblp add_pubmed
send_resp print print_nodoi num num_nodoi getref getref_nodoi append
);
%EXPORT_TAGS = (all => \@EXPORT_OK);

sub new {
    my $self;
    # defaults
    $self->{refs} = []; # the references
    $self->{nodoi_refs} = []; 
    $self->{duprefs} = [];
    $self->{html}=0;
    $self->{ratelimit}=5; # limit of 5 crossref queries per sec
    $self->{last} = {};
    bless $self;
  
    my $ratelimit = $_[1];
    if (defined($ratelimit) && ($ratelimit>=0)) {$self->{ratelimit}=$ratelimit};
    return $self;
}

sub sethtml {
  my $self = shift @_;
  $self->{html}=1;
}

sub clearhtml {
  my $self = shift @_;
  $self->{html}=0;
}

sub _err {
  my ($self, $str) = @_;
  if ($self->{html}) {
    print "<p style='color:red'>",$str,"</p>";
  } else {
    print $str,"\n";
  }
}

sub _split_duplicates {
  # split list of references into three lists: one with refs that have unique doi's, one with no doi's
  #and one with all the rest (with duplicate doi's)
  my $self = shift @_;
  my @refs=@{$self->{refs}};
  
  my @newrefs;
  my @nodoi_refs;
  my @duprefs;
  foreach my $ref (@refs) {
    my $doi = $ref->doi();
    if (!defined($doi) || length($doi)==0) {push @nodoi_refs, $ref; next; }# skip entries with no DOI
    my $found = 0;
    foreach my $ref2 (@newrefs) {
      if ($ref2->doi() eq $doi) {
        $found = 1;
      }
    }
    if (!$found) {
      push @newrefs, $ref;
    } else {
      push @duprefs, $ref;
    }
  }
  $self->{refs} = \@newrefs;
  $self->{duprefs} = \@duprefs;
  $self->{nodoi_refs} = \@nodoi_refs;
}

sub append {
  # add new reference to end of existing list
  my $self = shift @_;
  my $ref = shift @_;
  push @{$self->{refs}}, $ref;
}

sub add_details {
  # given an array of raw strings, try to convert into paper references
  
  my $self = shift @_;
  foreach my $cites (@_) {
    $self->{last} = Bib::CrossRef->new();
    $self->{last}->parse_text($cites);
    $self->append($self->{last});
    sleep 1/(0.001+$self->{ratelimit}); # rate limit queries to crossref
  }
  $self->_split_duplicates();
}

sub add_google {
  # scrape paper details from google scholar personal page -- nb: no doi info on google, so use crossref.org to obtain this
  # nb: doesn't work with google scholar search results
  
  my $self = shift @_;
  my $url = shift @_;
  my $ua = LWP::UserAgent->new;
  $ua->agent('Mozilla/5.0');
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if ($res->is_success) {
    my $tree= HTML::TreeBuilder::XPath->new;
    $tree->parse($res->decoded_content);
    my @atitles=$tree->findvalues('//tr[@class="gsc_a_tr"]/td/a[@class="gsc_a_at"]');
    my @authors=$tree->findvalues('//tr[@class="gsc_a_tr"]/td/div[@class="gs_gray"][1]');
    my @jtitles=$tree->findvalues('//tr[@class="gsc_a_tr"]/td/div[@class="gs_gray"][2]');
    my $len1 = @atitles; my $len2 = @authors; my $len3 = @jtitles;
    if (($len1 != $len2) || ($len1 != $len3) || ($len2 != $len3)) {$self->_err("Problem parsing google page: mismatched $len1 titles/$len2 authors/$len3 journals.");return []}
    my @cites=();
    for (my $i = 0; $i<$len1; $i++) {
      # these are already utf8
      $authors[$i] = decode_entities($authors[$i]);
      $atitles[$i] = decode_entities($atitles[$i]);
      $jtitles[$i] = decode_entities($jtitles[$i]);
      $cites[$i] = $authors[$i].", ".$atitles[$i].", ".$jtitles[$i];
    }
    $self->add_details(@cites);
  } else {
    $self->_err("Problem with $url: ".$res->status_line);
  }
}

sub add_google_search {
  # scrape paper details from google scholar search results -- *not* from persons scholar home page

  my $self = shift @_;
  my $url = shift @_;
  my $ua = LWP::UserAgent->new;
  $ua->agent('Mozilla/5.0');
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if ($res->is_success) {
    my $tree= HTML::TreeBuilder::XPath->new;
    $tree->parse($res->decoded_content);
    my @atitles=$tree->findvalues('//div[@class="gs_ri"]/h3/a');
    my @authors=$tree->findvalues('//div[@class="gs_a"]');
    my $len1 = @atitles; my $len2 = @authors;
    if ($len1 != $len2) {$self->_err("Problem parsing google page: mismatched $len1 titles/$len2 authors.");return [];}
    my @cites=();
    for (my $i = 0; $i<$len1; $i++) {
      $authors[$i] = decode_entities($authors[$i]);
      $atitles[$i] = decode_entities($atitles[$i]);
      my $str = $authors[$i].", ".$atitles[$i];
      if (length($str)>5) { # a potentially useful entry ?
        push @cites, $authors[$i].", ".$atitles[$i];
      }
    }
    $self->add_details(@cites);
  } else {
    $self->_err("Problem with $url: ".$res->status_line);
  }
}

sub add_dblp {
  # get details using DBLP XML API
  
  my $self = shift @_;
  my $url = shift @_;
  my $maxnum = shift @_; if (!defined($maxnum)) {$maxnum=-1;}
  
  my $ua = LWP::UserAgent->new;
  $ua->agent('Mozilla/5.0');
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if ($res->is_success) {
    my $xs = XML::Simple->new();
    my $data = $xs->XMLin($res->decoded_content);
    my @cites = $data->{'r'};
    my $num=0;
    foreach my $c (@{$cites[0]}) {
      $num++; if ($maxnum>0 && $num>$maxnum) {last;}  # mainly for testing
      my $cite;
      my @k = keys %{$c};
      $cite = $c->{$k[0]};
      my $ee = $cite->{'ee'};
      if ($ee =~ m/dx.doi.org/) {
        # we have a DOI, lets call crossref
        $ee =~ s/http:\/\/dx.doi.org\///;
        $self->add_details($ee);
        next; # move on to next record
      }
      my $temp = $cite->{'year'};
      $temp .= ' '.$cite->{'title'};
      if (defined $cite->{'journal'}) {
        $temp .= ' '.$cite->{'journal'};
      } elsif (defined $cite->{'booktitle'}) {
        $temp .= ' '.$cite->{'booktitle'};
      }
      my $auth='';
      if (ref($cite->{'author'}) eq "HASH") {
        $auth = $cite->{'author'};
      } else {
        foreach my $au (@{$cite->{'author'}}) { $auth .= $au.", ";}
      }
      my $r = Bib::CrossRef->new;
      $r->parse_text($auth.' '.$temp);
      if ($r->score >= 1) {
        # found an ok match, lets use it
        $self->append($r);
        next; # move on
      }
      #next; # stop here for now
      
      # we got a poor match, lets use the rest of the dblp data
      $r = Bib::CrossRef->new;
      if (exists $cite->{'publtype'}) {
        $r->_setgenre($cite->{'publtype'});
      } elsif ($k[0] =~ m/article/) {
        $r->_setgenre('article');
      } elsif ($k[0] =~ m/inproceedings/) {
        $r->_setgenre('proceeding');
      } else {
        $r->_setgenre($k[0]);
      }
      $r->_setatitle($cite->{'title'});
      if (defined $cite->{'journal'}) {
        $r->_setjtitle($cite->{'journal'});
      } elsif (defined $cite->{'booktitle'}) {
        $r->_setjtitle($cite->{'booktitle'});
      }
      $auth='';
      if (ref($cite->{'author'}) eq "HASH") {
        $r->_setauthcount(1);
        $r->_setauth(1,$cite->{'author'});
        $auth = $cite->{'author'};
      } else {
        my $count = 0;
        foreach my $au (@{$cite->{'author'}}) {
          $count++;
          $r->_setauth($count, $au);
          $auth .= $au.", ";
        }
        $r->_setauthcount($count);
      }
      if (defined $cite->{'volume'}) {$r->_setvolume($cite->{'volume'});}
      if (defined $cite->{'number'}) {$r->_setissue($cite->{'number'});}
      if (defined $cite->{'pages'}) {
        my @bits = split('-',$cite->{'pages'});
        if (defined $bits[0]) {$r->_setspage($bits[0]);}
        if (defined $bits[1]) {$r->_setepage($bits[1]);}
      }
      if (($cite->{'ee'} =~ m/^http:\/\//))  {
        $r->_seturl($cite->{'ee'});
      }
      $r->_setscore(1);
      $r->_setquery($auth." ".$temp);
      # add manually constructed record
      $self->append($r);
    }
    $self->_split_duplicates();
  } else {
    $self->_err("Problem with $url: ".$res->status_line);
  }
}

sub _get_orcid_doi {
  my $cite = shift @_;
  
  my $doi='';
  if (ref($cite->{'work-external-identifiers'}->{'work-external-identifier'}) eq "HASH") {
    # a single value
    my $id = $cite->{'work-external-identifiers'}->{'work-external-identifier'};
    if ($id->{'work-external-identifier-type'} =~ m/doi/) {
      # and its a DOI
      $doi =  $id->{'work-external-identifier-id'};
    } else {
      #print("Note: no DOI in ORCID for:".$cite->{'work-title'}->{'title'}.", only ".$id->{'work-external-identifier-type'}."=".$id->{'work-external-identifier-id'}."\n");
    }
  } else {
    # multiple values
    my $found = 0; my $types;
    foreach my $id (@{$cite->{'work-external-identifiers'}->{'work-external-identifier'}}) {
      if ($id->{'work-external-identifier-type'} =~ m/doi/) {
        # its a DOI
        $doi =  $id->{'work-external-identifier-id'};
        $found=1;
        last; # exit loop
      }
      $types = $types.$id->{'work-external-identifier-type'}.'='.$id->{'work-external-identifier-id'}." ";
    }
    if (!$found) {
      #print("Note: no DOI in ORCID for:".$cite->{'work-title'}->{'title'}.", only $types \n");
    }
  }
  return $doi;
}

sub _get_orcid_auth {
  my $cite = shift @_;

  my $auth='';
  if (ref($cite->{'work-contributors'}->{'contributor'}) eq "HASH") {
    # single author
    my $au = $cite->{'work-contributors'}->{'contributor'};
    if ($au->{'contributor-attributes'}->{'contributor-role'} =~ m/author/) {$auth = $au->{'credit-name'}->{'content'};}
  } else {
    # multiple authors
    foreach my $au (@{$cite->{'work-contributors'}->{'contributor'}}) {
      if ($au->{'contributor-attributes'}->{'contributor-role'} =~ m/author/) {$auth .= $au->{'credit-name'}->{'content'}.", ";}
    }
  }
  return $auth;
}

sub add_orcid {
  # get paper details from orcid using API
  
  my $self = shift @_;
  my $orcid_id = shift @_;
  my $ua = LWP::UserAgent->new;
  my $req = HTTP::Request->new(GET => "http://pub.orcid.org/$orcid_id/orcid-works/");
  my $res = $ua->request($req);
  if ($res->is_success) {
    my $xs = XML::Simple->new();
    # the orcid response is utf8 xml
    my $data = $xs->XMLin($res->decoded_content);
    my @cites = $data->{'orcid-profile'}->{'orcid-activities'}->{'orcid-works'}->{'orcid-work'};
    foreach my $cite (@{$cites[0]}) {
      my $ref={};
      my $doi = _get_orcid_doi($cite);
      if (defined $doi) {
        # use DOI to search.crossref.org
        my $r = Bib::CrossRef->new;
        $r->parse_text($doi);
        $self->append($r);
        next;  # move on
      }
      # use title etc to search.crossref.org
      my $temp='';
      if (exists $cite->{'publication-date'}->{'year'}) {$temp = $cite->{'publication-date'}->{'year'};}
      if (exists $cite->{'work-title'}->{'title'}) {$temp .= ' '.$cite->{'work-title'}->{'title'};}
      if (exists $cite->{'journal-title'}) {$temp = ' '.$cite->{'journal-title'};}
      my $auth = _get_orcid_auth($cite);
      my $r = Bib::CrossRef->new;
      $r->parse_text($auth.' '.$temp);
      if ($r->score >= 1) {
        # found an ok match, lets use it
        $self->append($r);
        next; # move on
      }
    
      #next; # stop here for now

      # for a poor match, try to extract rest of info from orcid
      $r = Bib::CrossRef->new;
      
      if (exists $cite->{'work-title'}->{'title'}) {$r->_setatitle($cite->{'work-title'}->{'title'});}
      if (exists $cite->{'journal-title'}) {$r->_setstitle($cite->{'journal-title'});}
      if (exists $cite->{'publication-date'}->{'year'}) {$r->_setdate($cite->{'publication-date'}->{'year'});}
      if (exists $cite->{'work-type'}) {$r->_setgenre($cite->{'work-type'});}
      
      my $authcount=0; $auth='';
      if (ref($cite->{'work-contributors'}->{'contributor'}) eq "HASH") {
        # single author
        my $au = $cite->{'work-contributors'}->{'contributor'};
        if ($au->{'contributor-attributes'}->{'contributor-role'} =~ m/author/) {
          $authcount++;
          $r->_setauth($authcount,$au->{'credit-name'}->{'content'});
          $auth = $au->{'credit-name'}->{'content'};
        }
      } else {
        # multiple authors
        foreach my $au (@{$cite->{'work-contributors'}->{'contributor'}}) {
          if ($au->{'contributor-attributes'}->{'contributor-role'} =~ m/author/) {
            $authcount++;
            $r->_setauth($authcount,$au->{'credit-name'}->{'content'});
            $auth .= $au->{'credit-name'}->{'content'}.", ";
          }
        }
      }
      $r->_setauthcount($authcount);
      
      if ($cite->{'work-citation'}->{'work-citation-type'} =~ m/bibtex/) {
        # we have a bibtex reference, extract some extra info
        # -- seems better to use crossref as this content can be messy
        my $bibtex = $cite->{'work-citation'}->{'citation'};
        open my $fh, '<', \$bibtex;
        my $parser = BibTeX::Parser->new($fh);
        my $entry = $parser->next;
        if ($entry->parse_ok) {
          if (defined $entry->field('volume')) {$r->_setvolume($entry->field('volume'))};
          if (defined $entry->field('issue')) {$r->_setissue($entry->field('issue'))};
          if (defined $entry->field('pages')) {
            my $pages = $entry->field('pages');
            (my $s, my $e) = ($pages =~ /([0-9]+)-+([0-9]+)/ );
            if (defined $s) { $r->_setspage($s); }
            if (defined $e) { $r->_setepage($e); }
          }
          if (defined $entry->field('journal')) {
            $r->_setjtitle($entry->field('journal'));
          } elsif (defined $entry->field('booktitle')) {
            $r->_setjtitle($entry->field('booktitle'));
          }
          my $jtitle = $r->jtitle;
          if (defined $jtitle ) {
            # tidy up
            $jtitle =~ s/[\{\}]//g;
            $jtitle =~ s/\\textquotesingle/\\'/g;
            $r->_setjtitle($jtitle);
          }
        }
      }
      $r->_setscore(1);
      $r->_setquery($auth." ".$temp);
      # add manually constructed record
      $self->append($r);
    }
    $self->_split_duplicates();
  } else {
    $self->_err("Problem with orcid.org: ".$res->status_line);
  }
}

sub _find_pubmed {
  my $c = shift @_;
  my $name = shift @_;
  my $term = shift @_;
  foreach my $item (@{$c}) {
    if ($item->{'Name'} eq $name) {
      return $item->{$term};
    }
  }
  return undef;
}

sub add_pubmed {
  # add results from a pubmed query
  my ($self,$q) = @_;

  my $ua = LWP::UserAgent->new;
  $q =~ s/\s+/+/g;
  my $req = HTTP::Request->new(GET => "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?usehistory=y&db=pubmed&term=".$q);
  my $res = $ua->request($req);
  if ($res->is_success) {
    my $web = $1 if ($res->decoded_content =~ /<WebEnv>(\S+)<\/WebEnv>/);
    my $key = $1 if ($res->decoded_content =~ /<QueryKey>(\d+)<\/QueryKey>/);
    $req = HTTP::Request->new(GET => "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&query_key=$key&WebEnv=$web");
    $res = $ua->request($req);
    if ($res->is_success) {
      my $xs = XML::Simple->new();
      my $data = $xs->XMLin($res->decoded_content);
      my @cites = $data->{'DocSum'};
      foreach my $cite (@{$cites[0]}) {
        my $c = $cite->{'Item'};
        if (ref($c) ne "ARRAY") {next;}
        my $r = Bib::CrossRef->new;
        my $doi = _find_pubmed($c,'DOI','content');
        if (defined $doi) {
          # PubMed is reliable, no need to call crossref
        #  my $r = Bib::CrossRef->new;
        #  $r->parse_text($doi);
        #  $self->append($r);
        #  next; # move on
          $r->_setdoi($doi);
          $r->_seturl('http://dx.doi.org/'.$doi);
        }
        $r->_setjtitle(_find_pubmed($c,'FullJournalName','content'));
        $r->_setatitle(_find_pubmed($c,'Title','content'));
        my $date = _find_pubmed($c,'PubDate','content');
        $date =~ m/^([0-9][0-9][0-9][0-9])/;
        $r->_setdate($1); # extract the year
        $r->_setvolume(_find_pubmed($c,'Volume','content'));
        $r->_setissue(_find_pubmed($c,'Issue','content'));
        my $p = _find_pubmed($c,'Pages','content');
        my @bits = split('-',$p);
        $r->_setspage($bits[0]); $r->_setepage($bits[1]);
        
        my $aulist = _find_pubmed($c,'AuthorList','Item');
        my $authcount=0;
        if (ref($aulist) ne "ARRAY") {
          $authcount = 1;
          $r->_setauth($authcount,$aulist->{'content'});
        } else {
          foreach my $au (@{$aulist}) {
            $authcount++;
            $r->_setauth($authcount,$au->{'content'});
          }
        }
        $r->_setauthcount($authcount);
        my $g = _find_pubmed($c,'FullJournalName','Item');
        $r->_setgenre($g->{'content'});
        $r->_setscore(1);
        #$r->_setquery($auth." ".$temp);
        # add manually constructed record
        $self->append($r);
      }
    }
    $self->_split_duplicates();
    return;
  }
  $self->_err("Problem with http://eutils.ncbi.nlm.nih.gov: ".$res->status_line);
}

sub add_fromfile {
  # read free text references from a file, one reference per line
  # takes file handle as input
  my $self = shift @_;
  my $fh = shift @_;
  my @cites;
  while (my $line=<$fh>) {
    chomp($line);
    if (length($line)<5) {next;}  # skip non-informative lines
    push @cites, $line;
  }
  $self->add_details(@cites);
}

sub num {
  # number of references with DOIs
  my $self = shift @_;
  
  my $len = @{$self->{refs}};
  return $len;
}

sub num_nodoi {
  # number of references without DOIs
  my $self = shift @_;
  
  my $len = @{$self->{nodoi_refs}};
  return $len;
}

sub getref {
 # get i'th reference with a DOI
 my ($self, $i) = @_;
 return ${$self->{refs}}[$i];
}

sub getref_nodoi {
 # get i'th reference without a DOI
 my ($self, $i) = @_;
 
 return ${$self->{nodoi_refs}}[$i];
}

sub print {
  # display a list of references
  my $self = shift @_;
  my $id = shift @_;
  
  if ($self->num==0) {return ''};
  my $out='';
  if ($self->{html}) {$out.=$self->getref(0)->printheader($id);}
  for (my $i=0; $i< $self->num; $i++) {
    if ($self->{html}) {$self->getref($i)->sethtml;} else {$self->getref($i)->clearhtml;}
    $out .= $self->getref($i)->print($i+1);
    $out .= "\n";
  }
  if ($self->{html}) {$out.=$self->getref(0)->printfooter;}
  return $out;
}

sub print_nodoi {
  # display a list of references
  my $self = shift @_;
  my $id = shift @_;
  
  if ($self->num_nodoi==0) {return ''};
  my $out='';
  if ($self->{html}) {$out.=$self->getref_nodoi(0)->printheader($id);}
  for (my $i=0; $i< $self->num_nodoi; $i++) {
    if ($self->{html}) {$self->getref_nodoi($i)->sethtml;} else {$self->getref_nodoi($i)->clearhtml;}
    $out .= $self->getref_nodoi($i)->print($i+1);
  }
  if ($self->{html}) {$out.=$self->getref_nodoi(0)->printfooter;}
}

sub send_resp {
  # generate simple web page with results ...
  
  my $self = shift @_;

  if ($self->num==0 && $self->num_nodoi==0) {return ''};
  my $html = $self->{html};
  $self->sethtml; # force use of html
  my $out='';
  #$out.="Content-Type: text/html;\n\n"; # html header
  $out.=sprintf "%s", '<!DOCTYPE HTML>',"\n";
  $out.=sprintf "%s", '<html><head><meta charset="utf-8"><meta http-equiv="Content-Type">';
  $out.=sprintf "%s", '<script src="post.js"></script></head><body>',"\n";
  $out.=sprintf "%s", $self->print('doi');
  if ($self->num_nodoi>0) {
    $out.=sprintf "%s", '<h3>These have no DOIs:</h3>',"\n";
    $out.=sprintf "%s", $self->print_nodoi('nodoi');
  }
  $out.=sprintf "%s", '<input id="Submit" type="button" value="Submit" onclick="GetCellValues(\'doi\');" /><div id="out"></div>';
  $out.=sprintf "%s", '</body></html>';
  $self->{html} = $html; # restore previous setting
  return $out;
}

1;

=pod
 
=head1 NAME
 
Bib::Tools - For managing collections of Bib::CrossRef references.
 
=head1 SYNOPSIS

 use strict;
 use Bib::Tools;
 
# Create a new object

 my $refs = Bib::Tools->new();
 
# Add some bibliometric info e.g. as text, one reference per line

 $text=<<"END";
 10.1109/lcomm.2011.040111.102111
 10.1109/tnet.2010.2051038
 END
 open $fh, '<', \$text;
 $refs->add_fromfile($fh);
 
 or 
 
 $text=<<"END";
 Dangerfield, I., Malone, D., Leith, D.J., 2011, Incentivising fairness and policing nodes in WiFi, IEEE Communications Letters, 15(5), pp500-502
 D. Giustiniano, D. Malone, D.J. Leith and K. Papagiannaki, 2010. Measuring transmission opportunities in 802.11 links. IEEE/ACM Transactions on Networking, 18(5), pp1516-1529
 END
 open $fh, '<', \$text;
 $refs->add_fromfile($fh);

# or as text scraped from a google scholar personal home page

 $refs->add_google('http://scholar.google.com/citations?user=n8dX1fUAAAAJ');

# or as text obtained from ORCID (www.orcid.org)

 $refs->add_orcid('0000-0003-4056-4014');

# or as text from PubMed

 $refs->add_pubmed('mills kh[author]');
 
# or as text from DBLP

 $refs->add_dblp('http://www.informatik.uni-trier.de/~ley/pers/xx/l/Leith:Douglas_J=');

# Bib:Tools will use Bib:CrossRef to try to resolve the supplied text into full citations.  It will try to 
detect duplicates using DOI information, so its fairly safe to import from multiple sources without creating 
clashes.  Full citations without DOI information are kept separately from those with a DOI for better quality
control.

# The resulting list of full citations containing DOI's can be printed out in human readable form using

 print $refs->print;

# and the list of full citations without DOI's

 print $refs->print_nodoi;

# or the complete citation list can also be output as a simple web page using

 print $refs->send_resp;

=head1 METHODS
 
=head2 new

 my $refs = Bib::Tools->new();

Creates a new Bib::Tools object.  Queries to crossref via Bib::CrossRef are rate limited.  To change the ratelimit pass this as
an option to new e.g $refs = Bib::Tools->new(3) sets the rate limit to 3 queries per second.

=head2 add_google

 $refs->add_google($url);
 
Scrapes citation information from a google scholar personal home page (*not* a search page, see below) and tries 
resolve it into full citations using crossref.

=head2 add_google_search

 $refs->add_google_search($url);
 
Scrapes citation information from a google scholar search page and tries to resolve into full citations.  A different
method is needed for search and home pages due to the different html tags used.

=head2 add_orcid

 $refs->add_orcid($orcid_id);
 
Uses the ORCID API to extract citations for the specified user identifier.  If possible, the DOI is obtained and then resolved using crossref.

=head2 add_dblp

 $refs->add_dblp($url);
 
Uses DBLP XML API to extract citations.  If possible, the DOI is obtained and then resolved using crossref.   E.g.

 $refs->add_dblp('http://www.informatik.uni-trier.de/~ley/pers/xx/l/Leith:Douglas_J=');
 
=head2 add_pubmed
 
 $refs->add_dblp($query);
 
Uses PubMed API to extract citations listed in response to a query. E.g.

 $refs->add_pubmed('mills kh[author]');
 
=head2 add_details

 $refs->add_details(@lines);
 
Given a array of strings, one per citation, tries to resolve these into full citations.

=head2 add_fromfile

 $refs->add_fromfile($fh);
 
Given a file handle to a text file, with one citation per line, tries to resolve these into full citations.  
 
=head2 print

 my $info = $refs->print;

Display the list of full citations that have DOIs in human readable form.

=head2 print_nodoi

 my $info = $refs->print_nodoi;

Display the list of full citations without DOIs in human readable form.

=head2 sethtml

 $refs->sethtml
 
Set the output format to be html

=head2 clearhtml

 $refs->clearhtml
 
Set the output format to be plain text

=head2 send_resp

 my $info = $refs->send_resp;

=head2 num

 my $num = $refs->num;
 
Returns the number of full citations that have DOIs

=head2 num_nodoi

 my $num = $refs->num_nodoi;
 
Returns the number of full citations without DOIs

=head2 getref

 my $ref = $refs->getref($i);
 
Returns the $i citation from the list with DOIs.  This can be used to walk the list of citations.

=head2 getref_nodoi

 my $ref = $refs->getref_nodoi($i);

Returns the $i citation from the list without DOIs

=head2 append

  my $ref = Bib::CrossRef->new;
  $refs->append($ref);

Adds a Bib::CrossRef to end of a Bib::Tools list of objects

=head1 EXPORTS
 
You can export the following functions if you do not want to use the object orientated interface:

sethtml clearhtml add_details add_google add_google_search add_orcid add_fromfile add_dblp add_pubmed
send_resp print print_nodoi num num_nodoi getref getref_nodoi append

The tag C<all> is available to easily export everything:
 
 use Bib::Tools qw(:all);

=head1 WEB INTERFACE

A simple web interface to Bib::Tools is contained in the scripts folder.  This consists of two files: query.html and handle_query.pl.

=head2 query.html

 <!DOCTYPE HTML>
 <html><head><meta http-equiv="Content-Type" content="text/html;charset=UTF-8"></head><body>
 <h3>Import References</h3>
 <form action="handle_query.pl" method="POST" id="in">
 <table>
 <tr><td>Use ORCID id:<br><small style="color:#C0C0C0">e.g. 0000-0003-4056-4014</small></td>
 <td><INPUT type="text" name="orcid" size="128"></p></td>
 </tr>
 <tr><td colspan=2>(to import from Scopus, follow these <a href="http://orcid.scopusfeedback.com/">instructions</a>)</td></tr>
 <tr><td>Use Google Scholar personal page:<br>
 <small style="color:#C0C0C0">e.g. http://scholar.google.com/citations?user=n8dX1fUAAAAJ</small></td>
 <td><INPUT type="text" name="google" size="128"></p></td>
 </tr>
 <tr><td>Use Google Scholar search page:<br>
 <small style="color:#C0C0C0">e.g. http://scholar.google.com/scholar?q=andr%C3%A9s+garcia+saavedra</small></td>
 <td><INPUT type="text" name="google2" size="128"></p></td>
 </tr>
 <tr><td>Use DBLP page:<br>
 <small style="color:#C0C0C0">e.g. 'http://www.informatik.uni-trier.de/~ley/pers/xx/l/Leith:Douglas_J=</small></td>
 <td> <INPUT type="text" name="dblp" size="128"></td></tr>
 <tr><td>Use PubMed query:<br>
 <small style="color:#C0C0C0">e.g. mills kh[author]</small></td>
 <td> <INPUT type="text" name="query" size="128"></td></tr>
 </table>
 <p>Enter references, one per line:</p><textarea name="refs" rows="10" cols="128" form="in"></textarea><br>
 <INPUT type="submit" value="Submit">
 </form>
 </body></html>

=head2 handle_query.pl

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
 if (length($google) > 5) {
   if (!($google =~ m/^http/)) { $google = "http://".$google;}
   $refs->add_google($google);
 }

 my $google2 = scalar $q->param('google2'); #NB: CGI has already carried out URL decoding
 if (length($google2) > 5) {
   if (!($google2 =~ m/^http/)) { $google2 = "http://".$google2;}
   $refs->add_google_search($google2);
 }

 my $dblp = scalar $q->param('dblp');
 if (length($dblp) > 5) {
   if (!($dblp =~ m/^http/)) { $dblp = "http://".$dblp;}
   if ($dblp =~ m/http:\/\/dblp.uni-trier.de\/pers\/xx\/l\/.+/) {
      # looks like a valid dblp url
      $refs->add_dblp($dblp);
   } else {
      print "<p style='color:red'>DBLP url looks invalid: ", $dblp,"</p>";
   }
 }

 my $pubmed = scalar $q->param('pubmed');
 if (length($pubmed) > 5) {
   $refs->add_pubmed($pubmed);
 }
 
 my @values = $q->multi_param('refs');
 foreach my $value (@values) {
   open my $fh, "<", \$value; #NB: CGI has already carried out URL decoding
   $refs->add_fromfile($fh);
 }

 $refs->sethtml;
 print $refs->send_resp;

=head1 VERSION
 
Ver 0.09
 
=head1 AUTHOR
 
Doug Leith 
    
=head1 BUGS
 
Please report any bugs or feature requests to C<bug-rrd-db at rt.cpan.org>, or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Bib-Tools>.  I will be notified, and then you'll automatically be notified of progress on your bug as I make changes.
 
=head1 COPYRIGHT
 
Copyright 2015 D.J.Leith.
 
This program is free software; you can redistribute it and/or modify it under the terms of either: the GNU General Public License as published by the Free Software Foundation; or the Artistic License.
 
See http://dev.perl.org/licenses/ for more information.
 
=cut


__END__
