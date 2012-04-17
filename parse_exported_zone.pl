
use strict;
use warnings;
use DNS::ZoneParse;

my $in_file = shift or die usage("zone file not specified") ;
die usage("File: \'$in_file\' not found") if (! -f $in_file) ;

#my $origin = "kitd.com" ;
my $origin = shift or die usage("origin not specified") ;
my $origin_regex = $origin ;
   $origin_regex =~ s/\./\\./g ;
my %last_sds ;
my $last_sd ;
my $header_template_file = "templates/zoneheader" ;
my $header_template = "" ;
my $zone_subfix = ".zone.db" ;

open (HEADER_TEMPLATE_FILE, $header_template_file) or die qq(Could not open header_template_file $header_template_file: $!);
 while (<HEADER_TEMPLATE_FILE>) {
	$header_template = $header_template . $_ . "\n" ;
 }
close HEADER_TEMPLATE_FILE ;
    
my $zonefile = DNS::ZoneParse->new($in_file, $origin);
    
#I should be using dump instead, but i thorght of this first and kind of liked that i could use a var as a methord
#So have stuck with it for now

my @records_types = ("a", "cname", "srv", "mx", "ns", "ptr", "txt", "hinfo", "rp", "loc");

# chose which sub domains we want to brake out in to seperate zone files
# we could probally have this automated eg and sub with more the X names get auto broken out
# but manualy seems nicer for now. also this should be a Cl option, time to bust out getOps long
my @brakeouts = ("subzone1");


# start by importing the data from the zone file in to a hash of hashes based on the sub domain

foreach my $records_type (@records_types) {
    my $a_records = $zonefile->$records_type();
    next if scalar $a_records == "0";
    
    foreach my $record (@$a_records) {
	$record->{type} = uc($records_type);
	my $nqdn = lc($record->{name}) ;
	$nqdn =~ s/\.?$origin_regex\.?//g;
	$record->{nqdn} = lc($nqdn) ;
	my @nqdn_split = split(/\./,$nqdn) ;
	my $no_of_sd = scalar @nqdn_split ;
	if($no_of_sd > 1) {
		$last_sd = $nqdn_split[$no_of_sd-1] ;
	}else { $last_sd = " " ; 
	}

	push(@{$last_sds{$last_sd}}, $record);
	
 print "in $origin: sd:$no_of_sd \'$last_sd\', $nqdn \'$record->{name}\', \"$record->{ORIGIN}\", type:$record->{type}, pt:$record->{host},";
if ( $record->{type} eq "TXT" ) { print "\"$_->{text}\"" ; }
 print "\n";
    }
    
}
sub usage {
  my $extra_text = shift ;
  return <<USAGETEXT;
  $extra_text
usage: $0 "zone file" Origin
	process "zone file" and outputs it in a nicer format.
	Can split out the zone file into sub zone files, you need to edit the \@brakeouts var for this though
USAGETEXT
}


sub string_in_aray {
# sub to check if a given string matches "one of" the values in the @brakeouts aray
# returns True or False
	my $k = shift ;
	foreach (@brakeouts) { return ( "0" ) if $_ eq $k ; } 
		return ("1" ) ;
}

sub tab_out_string {
# Sub to add the corect amout of tabs, so that the zone files layout looks right
# 3 tabs is the default amount, but we can get 2 or 1 depending on the length of the string
	my $string = shift ;
	my $string_len = length($string) ;
	my $string_div = $string_len / 8 ;
	if ($string_div > 2) {
		$string_div = "2" ; }
	my $tabs = 3 ;
	$tabs = $tabs - $string_div ;

	my $out_tabs;
	while ( $tabs > 0 ) {
		$tabs-- ;
		$out_tabs = $out_tabs . "\t";
	}
	return($string . $out_tabs);
}
print "Generating Hash content\n";

my $new_zone ;
open($new_zone, '>','generated_zones/' . $origin . $zone_subfix ) or die "could not open zone file for w";
print $new_zone "$header_template" ;
foreach my $k (sort keys %last_sds) {
	print "$k: " . scalar @{$last_sds{$k}} . "\n";
	my $out_zone="" ;
	my $sub_zone ;
	my $new_line ;
	my @new_zones_lines ;
	if (!string_in_aray($k)) { 
	my $sub_origin = $k . '.' . $origin ;
	open($sub_zone, '>','generated_zones/' . $sub_origin . $zone_subfix ) or die "could not open zone file for w: $!";

	print $sub_zone "$header_template" ;
	print $sub_zone ";;$sub_origin :\n" ;
	 foreach (@{$last_sds{$k}}) {
		$_->{ORIGIN} = $sub_origin . '.' ;
		my $name = $_->{nqdn} ;
		$name =~ s/\.?$k//g ;
#		print $sub_zone "$name\t\t\t$_->{class}\t$_->{type}\t" . lc($_->{host}) . "\n"; 
		$new_line = tab_out_string($name) . "$_->{class}\t$_->{type}\t"; 
		if ( $_->{type} eq "MX" ) { $new_line = $new_line . "$_->{priority} " . lc($_->{host}) ; }
		elsif ( $_->{type} eq "TXT" ) { $new_line = $new_line . "\"$_->{text}\"" ; }
		else { $new_line = $new_line . lc($_->{host});}
		$new_line = $new_line . "\n";
		push(@new_zones_lines, $new_line);
	 }
	 @new_zones_lines = sort(@new_zones_lines);
	 foreach (@new_zones_lines) {
	  print $sub_zone "$_";

	 }
   	 print $new_zone "\n";

	close $sub_zone ;
	}
	else {
    	 print $new_zone ";;$k.$origin \n" if $k ne " ";
    	 print $new_zone ";;$origin \n" if $k eq " ";
   	 foreach (@{$last_sds{$k}}) {
		$new_line = tab_out_string($_->{nqdn}) . "$_->{class}\t$_->{type}\t"; 
		if ( $_->{type} eq "MX" ) { $new_line = $new_line . "$_->{priority} " . lc($_->{host}) ; }
		elsif ( $_->{type} eq "TXT" ) { $new_line = $new_line . "\"$_->{text}\"" ; }
		else { $new_line = $new_line . lc($_->{host});}
		$new_line = $new_line . "\n";
		push(@new_zones_lines, $new_line);
   	 }
	 @new_zones_lines = sort(@new_zones_lines);
	 foreach (@new_zones_lines) {
	  print $new_zone "$_";

	 }
   	 print $new_zone "\n"
	}
}

   print $new_zone "\n\n";
   close $new_zone ;
