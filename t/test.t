#!perl 

use Test::More tests => 24;
#use Data::Dumper;

BEGIN {
    use_ok( 'Bib::Tools' ) || print "Bail out!\n";
}

note("tests without using network ...\n");

my $refs = new_ok("Bib::Tools");
is($refs->{ratelimit},5);

my $ref = new_ok("Bib::CrossRef");
my $r=$ref->{ref};
$r->{doi} = 'http://dx.doi.org/10.1080/002071700411304';
$r->{score} = 1;
$r->{atitle}='Survey of gain-scheduling analysis and design';
$r->{jtitle}='International Journal of Control';
$r->{volume}=1; $r->{issue}=2;
$r->{date}='2015'; $r->{genre}='article';
$r->{authcount}=2;
$r->{au1}='D. J. Leith'; $r->{au2}='W. E. Leithead';
$r->{spage}='1001'; $r->{epage}='1025';

$refs->{refs}->[0]=$ref;
$refs->{refs}->[1]=$ref;
ok($refs->_split_duplicates);
my $len1 = @{$refs->{refs}};
is($len1,1);
my $len2 = @{$refs->{duprefs}};
is($len2,1);
my $len3 = @{$refs->{nodoi_refs}};
is($len3,0);

is($refs->num,1);
is($refs->num_nodoi,0);
my $r1;
ok($r1 = $refs->getref(0));
my $out1;
ok($out1 = $r1->print(1));
my $out;
ok($out = $refs->print);
is($out,$out1."\n");
ok($out=$refs->send_resp);
my $expected=<<"END";
<!DOCTYPE HTML><html><head><meta charset="utf-8"><meta http-equiv="Content-Type"></head><body><table><tr style="font-weight:bold"><td></td><td>Use</td><td></td><td>Type</td><td><Year></td><td>Authors</td><td>Title</td><td>Journal</td><td>Volume</td><td>Issue</td><td>Pages</td><td>DOI</td></tr>
<tr><td>1</td><td><input type="checkbox" name="1" value="" checked></td><td></td><td contenteditable="true">article</td><td contenteditable="true">2015</td><td contenteditable="true">D. J. Leith, W. E. Leithead, </td><td contenteditable="true">Survey of gain-scheduling analysis and design</td><td contenteditable="true">International Journal of Control</td><td contenteditable="true">1</td><td contenteditable="true">2</td><td contenteditable="true">1001-1025</td><td contenteditable="true"><a href=http://dx.doi.org/10.1080/002071700411304>http://dx.doi.org/10.1080/002071700411304</a></td></tr>
<tr><td colspan=12 style="color:#C0C0C0"></td></tr>

</table>
</body></html>
END
is($out."\n",$expected);

note("tests requiring a network connection ...\n");

$refs = new_ok("Bib::Tools");
my @lines;
$lines[0]='25.	Dangerfield, I., Malone, D., Leith, D.J., 2011, Incentivising fairness and policing nodes in WiFi, IEEE Communications Letters, 15(5), pp500-502.';
$lines[1]='26.	D. Giustiniano, D. Malone, D.J. Leith and K. Papagiannaki, 2010. Measuring transmission opportunities in 802.11 links. IEEE/ACM Transactions on Networking, 18(5), pp1516-1529';
$refs->add_details(@lines);

SKIP: {
  skip "Optional network tests", 7 unless (defined ${$refs->{refs}}[0]);

  my $expected1 = 'article: 2011, I Dangerfield, D Malone, D J Leith, \'Incentivising Fairness and Policing Nodes in WiFi\'. IEEE Communications Letters, 15(5),pp500-502, DOI: http://dx.doi.org/10.1109/lcomm.2011.040111.102111';
  is(${$refs->{refs}}[0]->print,$expected1);
  my $expected2='article: 2010, Domenico Giustiniano, David Malone, Douglas J. Leith, Konstantina Papagiannaki, \'Measuring Transmission Opportunities in 802.11 Links\'. IEEE/ACM Transactions on Networking, 18(5),pp1516-1529, DOI: http://dx.doi.org/10.1109/tnet.2010.2051038';
  is(${$refs->{refs}}[1]->print,$expected2);
  ok($out=$refs->print());
$expected1='1. article: 2011, I Dangerfield, D Malone, D J Leith, \'Incentivising Fairness and Policing Nodes in WiFi\'. IEEE Communications Letters, 15(5),pp500-502, DOI: http://dx.doi.org/10.1109/lcomm.2011.040111.102111
2. article: 2010, Domenico Giustiniano, David Malone, Douglas J. Leith, Konstantina Papagiannaki, \'Measuring Transmission Opportunities in 802.11 Links\'. IEEE/ACM Transactions on Networking, 18(5),pp1516-1529, DOI: http://dx.doi.org/10.1109/tnet.2010.2051038
';  is($out,$expected1);

my $text=<<"END";
10.1109/lcomm.2011.040111.102111
10.1109/tnet.2010.2051038
END
  open $fh,"<",\$text;
  ok($refs->add_fromfile($fh));
  ok($out=$refs->print());
  is($out,$expected1);
}

diag( "Testing Bib::Tools $Bib::Tools::VERSION, Perl $], $^X" );
