#!/usr/bin/perl
# 
# Version: 0.1.0
# Author: Nathan S. Haigh
# 
# Not ideal as it won't scale well to many, many sequences as they are all read
# into memory first.
# 
# TODO: Use Boulder module for reading/writing Primer3 IO
# TODO: Use File::Temp to create temp files
# 

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
#use Bio::Tools::Primer3;
#use Data::Dumper;

my $VERSION = 0.1.0;

my vars ($temp_01, $temp_02, $temp_03);
END {
	print STDERR "Cleaning up temp files ... ";
	unlink $temp_01;
	unlink $temp_02;
	unlink $temp_03;
	print STDERR "DONE\n";
}



my $man = 0;
my $help = 0;

my ($infile,$result_file, $summary_file);
$temp_01 = 'input_01.txt';
$temp_02 = 'input_02.txt';
$temp_03 = 'primer3_01.out';

# Default Settings for Primer3
my $min_primer_f_tm = 55;
my $opt_primer_f_tm = 60;
my $max_primer_f_tm = 65;
my $min_primer_r_tm = 60;
my $opt_primer_r_tm = 65;
my $max_primer_r_tm = 70;
my $min_primer_length = 18;
my $max_primer_length = 36;
my $primer_self_comp_any = 8;
my $primer_self_comp_end = 6;
my $product_size = "36-350";

GetOptions (
	"infile=s"		=> \$infile,
	"result_file=s"		=> \$result_file,
	"summary_file=s"	=> \$summary_file,
	
	"asfp_min_tm=i"	=> \$min_primer_f_tm,
	"asfp_opt_tm=i"	=> \$opt_primer_f_tm,
	"asfp_max_tm=i"	=> \$max_primer_f_tm,

	"lsrp_min_tm=i"	=> \$min_primer_r_tm,
	"lsrp_opt_tm=i"	=> \$opt_primer_r_tm,
	"lsrp_max_tm=i"	=> \$max_primer_r_tm,
	
	"min_primer_length=i"	=> \$min_primer_length,
	"max_primer_length=i"	=> \$max_primer_length,
	
	"self_comp_any=i"	=> \$primer_self_comp_any,
	"self_comp_end=i"	=> \$primer_self_comp_end,
	
	"product_size=s"	=> \$product_size,
	
	'help|?'		=> \$help,
	'man'			=> \$man,
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

pod2usage(1) if ! ($infile && $result_file && $summary_file);

my %IUPAC = (
	'AG' => 'R',
	'CT' => 'Y',
	'GT' => 'K',
	'AC' => 'M',
	'CG' => 'S',
	'AT' => 'W',
	'CGT' => 'B',
	'AGT' => 'D',
	'ACT' => 'H',
	'ACG' => 'V',
	'ACGT' => 'N',
);

print STDERR "Generating allele-specific forward primers, please wait ...\n";
my (%subs, $desc);
open (INFILE, $infile) or die "Could not open input file: $!\n";
while (<INFILE>) {
	chomp;
	my $line = $_;
	#print "$line\n";
	#next;
	
	if ( $line =~ /^\>(.+?)$/ ) {		# new description line
		$desc = $1;
		chomp $desc;
		#print STDOUT "$desc\n";
		#next;
	} else {			# sequence line(s)
		$subs{$desc}{'original sequence'} .= $line;	# concat the sequences together
	}
}
close INFILE;

foreach my $desc ( keys %subs ) {
	my $sequence = $subs{$desc}{'original sequence'};
	my $SNP_no = 0;
	while ( $sequence =~ /\[(.+?)\]/g ) {
		my $SNP = uc($1);
		my $prematch = lc($`);	# just to fix syntax highlighting in gedit --> `
		my $postmatch = lc($');	# just to fix syntax highlighting in gedit --> '
		$SNP_no ++;
		$prematch =~ s/^.+\]//;	# only take tail end of pretmatch upto next SNP
		$postmatch =~ s/\[.+$//;	# only take leading end of postmatch upto next SNP
		
		my @alleles = split(/\//, $SNP);
		
		if (grep(/^\*$/, @alleles)) {	# have an indel in the allele
			my @insertions = grep(!/^\*$/, @alleles);
			#push @{$subs{$desc}{'SNP IUPAC'}}, "";
			print STDERR "\tWARNING: SKIPPING indel in $desc:\t$SNP\n";	#\t@insertions";
			
		} else {
			my $key = join('', sort@alleles);
			if (exists $IUPAC{$key}) {
				#push @{$subs{$desc}{'SNP IUPAC'}}, $IUPAC{$key};
				

				#print "$sequence\n";
				foreach my $allele ( @alleles ) {

					# Check the pre/post match sequence + allele are long enough for the minimum primer length
					if ( length($prematch.$allele) >= $min_primer_length ) {
						# design a set of primers for this allele in the normal strand (+)
						#print "$prematch\t$allele\t$postmatch\n";
						push @{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}{'+'}}, design_primers($sequence, $prematch.$allele, $min_primer_length, $max_primer_length);
						
					} else {
						# not enough room for any SNP specific primers on the normal strand
						#$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}{'+'} = [];
					}
					if ( length($postmatch.$allele) >= $min_primer_length ) {
						# design a set of primers for this allele in the complementary strand (-)
						#print "$postmatch\n";
						push @{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}{'-'}}, design_primers($sequence, revcomp($allele.$postmatch), $min_primer_length, $max_primer_length);
					} else {
						# not enough room for any SNP specific primers on the rev comp strand
						#$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}{'-'} = [];
					}
					
					if ( length($prematch.$allele) < $min_primer_length && length($postmatch.$allele) < $min_primer_length ) {
						# not enough room for any SNP specific primers on the rev comp strand OR the normal strand
						$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}{'+'} = [];
						$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}{'-'} = [];
					}
				}
				
			} else {
				print STDERR "\tWARNING: Couldn't find IUPAC code for SNP: $SNP ($key) in sequence: $desc - SKIPPING SEQUENCE\n";
				delete($subs{$desc});
			}
			#print STDERR "SNP:\t$SNP\t$key\n";
		}
	}
	
}
print STDERR "DONE\n";
#print STDERR Dumper(%subs);

# create a primer3 input command file
open (PRIMER3INPUT, ">$temp_01") or die "Couldn't open file to write Primer3 commands to";
my $total_primers_to_check = 0;
#print "Description\tSNP Number\tAllele\tStrand\tNumber of SNP specific primers tested\n";
foreach my $desc ( sort keys %subs ) {
	foreach my $SNP_no (sort {$a<=>$b} keys %{$subs{$desc}{'SNP'}} ) {
		if (keys %{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}} == 0) {
			#print "$desc\t$SNP_no\n";
		}
		foreach my $allele (sort keys %{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}} ) {
			foreach my $strand (sort keys %{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}} ) {
				my $primers = $subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}{$strand};
				my $no_primers = scalar@{$primers};
				$total_primers_to_check += $no_primers;
				#print "$desc\t$SNP_no\t$allele\t$strand\t$no_primers\n";
				
				append_primer3_commands($subs{$desc}{'original sequence'}, $primers, $desc, $SNP_no, $allele, $strand);
			}
		}
	}
	#print "\n";
}
#print "Total SNP specific primers to check\t$total_primers_to_check\n";
close PRIMER3INPUT;

# Run Primer3
#############
print STDERR "Calculating allele-specific forward primer properties, please wait ... ";
system("primer3 < $temp_01 > $temp_03");
print STDERR "DONE\n";

# Parse Primer3 output
######################
print STDERR "Parsing allele-specific forward primer properties, please wait ... ";
_parse_primer3_output($temp_03, $temp_02);
print STDERR "DONE\n";

print STDERR "Finding suitable locus-specific reverse primers, please wait ... ";
my $result_file_tmp = $result_file.'_tmp';
system("primer3 < $temp_02 > $result_file_tmp");
print STDERR "DONE\n";

print STDERR "Preparing SNP-SCALE Primer Designer summary, please wait ... ";
generate_summary($result_file_tmp, $result_file, $summary_file);
print STDERR "DONE\n";

##############################
######## SUB ROUTINES ########
##############################

sub generate_summary {
	my ($in, $results, $summary_file) = @_;
	
	
	
	open(IN, $in) or die "Could not open results file: $!\n";
	open(RESULT, ">$results") or die "Could not open file: $!\n";
	$/ = "\n=\n";	# set the record seperator
	my $record_no = 0;
	my $with_primer_pairs_no = 0;
	while (<IN>) {
		$record_no++;
		chomp;
		my $record = $_;
		my %primer_result = split /[=\n]/, $record;
		
		$primer_result{'PRIMER_SEQUENCE_ID'} =~ /^(.+?)\s\[(.+?)\]$/;
		my $desc = $1;
		my %primer_ids = split /[\:\|]/, $2;
		my $gene_sequence = $primer_result{'SEQUENCE'};
		
		# Do something with each result file
		if ( exists $primer_result{'PRIMER_LEFT'} && exists $primer_result{'PRIMER_RIGHT'} ) {
			# we have at least 1 of each
			print RESULT "$record\n=\n";
			push @{$subs{$desc}{'SNP'}{$primer_ids{'SNP'}}{'allele'}{$primer_ids{'Allele'}}{'primer pairs'}{$primer_ids{'Strand'}}}, $record;
			$with_primer_pairs_no++;
		} else {
			
		}
	}
	close RESULT;
	close IN;
	unlink $in;
	
	#print "\n\tTotal records: $record_no";
	#print "\n\tRecords with primer pairs: $with_primer_pairs_no\n";
	
	open (SUMMARY, ">$summary_file") or die "Could not open summary file: $!\n";
	print SUMMARY "Description\tSNP Number\tAllele\tStrand\tNumber of SNP specific primers tested\tNumber of primer pair candidates found\n";
	foreach my $desc ( sort keys %subs ) {
		foreach my $SNP_no (sort {$a<=>$b} keys %{$subs{$desc}{'SNP'}} ) {
			if (keys %{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}} == 0) {
				print SUMMARY "$desc\t$SNP_no\n";
			}
			foreach my $allele (sort keys %{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}} ) {
				foreach my $strand ( sort keys %{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}} ) {
					my $tested = scalar@{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'SNP primers'}{$strand}};
					my $no_primer_pairs = 0;
					
					foreach my $record ( @{$subs{$desc}{'SNP'}{$SNP_no}{'allele'}{$allele}{'primer pairs'}{$strand}} ) {
						my %primer_result = split /[=\n]/, $record;
						
						# Extract info from record such that primer info can be diaplayed in a table
						# the whole PRIMER_(LEFT|RIGHT)_((\d+)_)?SEQUENCE could make things messy
						if ( exists $primer_result{'PRIMER_LEFT'} && exists $primer_result{'PRIMER_RIGHT'} ) {
							# we have at least one primer pair
							$no_primer_pairs++;
						}
					}
					print SUMMARY "$desc\t$SNP_no\t$allele\t$strand\t$tested\t$no_primer_pairs\n";
				}
			}
		}
	}
	close SUMMARY;
}

sub _parse_primer3_output {
	my ($file, $primer3_command_file) = @_;
	my %primer_results;
	
	open (OUT, ">$primer3_command_file") or die "Could not open output file: $!\n";
	$/ = "\n=\n";	# set the record seperator
	open (IN, $file) or die "Could not open file for reading\n";
	while (<IN>) {
		chomp;
		my $record = $_;
		my %primer_result = split /[=\n]/, $record;
		my $side;
		$primer_result{'PRIMER_SEQUENCE_ID'} =~ /^(.+?)\s\[(.+?)\]$/;
		my $desc = $1;
		my %primer_ids = split /[\:\|]/, $2;
		my $gene_sequence = $primer_result{'SEQUENCE'};
		
		if (exists $primer_result{'PRIMER_LEFT_INPUT'}) {
			$side = 'LEFT';
		} else {
			$side = 'RIGHT';
		}
		
		#next unless exists $primer_result{'PRIMER_'.$side.'_TM'};
		
		# now only dealing with primers that met the first set of criteria
		# so remove the PRIMER_TASK and change the PRIMER_OPT_TM and PRIMER_MAX_TM
		# so that the other primer can be found with the correct criteria
		# then print to a new primer input file and run primer3 again
		delete $primer_result{'PRIMER_TASK'};
		$primer_result{'PRIMER_OPT_TM'} = $opt_primer_r_tm;
		$primer_result{'PRIMER_MAX_TM'} = $max_primer_r_tm;

		foreach my $key (keys %primer_result) {
			print OUT "$key=", $primer_result{$key}, "\n";
		}
		print OUT "=\n";

		#my $primer_seq = $primer_result{'PRIMER_'.$side.'_INPUT'};
		#my $primer_tm = $primer_result{'PRIMER_'.$side.'_TM'};
		
		#print "$desc\t$primer_seq\t$primer_tm\n";
	}
	close IN;
	close OUT;
}
sub revcomp {
	my ($seq) = @_;
	$seq = reverse($seq);
	$seq =~ tr/ATGCatgc/TACGtacg/;
	return $seq;
}

sub design_primers {
	my ($gene_seq, $sequence, $min_size, $max_size) = @_;
	my @primers;

	for (my $i=$min_size; $i<=$max_size; $i++) {
		last if $i > length($sequence);
		push @primers, substr $sequence, 0-$i;
	}

	return @primers;
}

sub append_primer3_commands {
	my ($sequence, $primers, $desc, $SNP_no, $allele, $strand) = @_;
	#print "$desc\t$SNP_no\t$allele\t$strand\n";
	
	# Create the correct SEQUENCE by substituting the $allele into the correct SNP [.+?] location
	# and changing all other [.+?] SNPs into an 'N'
	my $SNP_pos = 0;
	while ( $sequence =~ /\[.+?\]/g ) {
		$SNP_pos++;
		if ($SNP_pos == $SNP_no) {
			# take prematch and postmatch and sub in 'N' in place of [.+?]
			# Take this SNP and sub in the $allele
			my $prematch = lc($`);	# just to fix syntax highlighting in gedit --> `
			my $postmatch = lc($');	# just to fix syntax highlighting in gedit --> '
			my $match = $&;
			$prematch =~ s/\[.+?\]/N/g;
			$postmatch =~ s/\[.+?\]/N/g;
			$match =~ s/\[.+?\]/$allele/;
			$sequence = "$prematch$match$postmatch";
		}
	}
		
	
	foreach my $primer ( @{$primers} ) {
		my $primer_length = length($primer);
		print PRIMER3INPUT "PRIMER_SEQUENCE_ID=$desc [SNP:$SNP_no|Allele:$allele|Strand:$strand|Primer length:$primer_length]\n";
		print PRIMER3INPUT "SEQUENCE=$sequence\n";
		print PRIMER3INPUT "PRIMER_PRODUCT_SIZE_RANGE=$product_size\n";
		
		if ($strand eq '+') {
			
			print PRIMER3INPUT "PRIMER_TASK=pick_left_only\n";
			print PRIMER3INPUT "PRIMER_LEFT_INPUT=$primer\n";

		} elsif ($strand eq '-') {
			#print PRIMER3INPUT "SEQUENCE=",revcomp($sequence),"\n";
			print PRIMER3INPUT "PRIMER_TASK=pick_right_only\n";
			print PRIMER3INPUT "PRIMER_RIGHT_INPUT=$primer\n";

		} else {
			die "Unknow strand type: $strand. Must be either + or -";
		}
		print PRIMER3INPUT "PRIMER_SELF_ANY=$primer_self_comp_any\n";
		print PRIMER3INPUT "PRIMER_SELF_END=$primer_self_comp_end\n";

		print PRIMER3INPUT "PRIMER_MIN_TM=$min_primer_f_tm\n";
		print PRIMER3INPUT "PRIMER_OPT_TM=$opt_primer_f_tm\n";
		print PRIMER3INPUT "PRIMER_MAX_TM=$max_primer_f_tm\n";
		
		print PRIMER3INPUT "PRIMER_MIN_SIZE=$min_primer_length\n";
		print PRIMER3INPUT "PRIMER_MAX_SIZE=$max_primer_length\n";
		
		print PRIMER3INPUT "=\n";
	}
}

=head1 SNP-SCALE Primer Designer

Design primers suitable for use with the Multiplex SNP-SCALE methodology.

=head1 VERSION

0.1.0

=head1 SYNOPSIS

B<snp-scale_pd.pl> B<-infile> I<filename> B<-summary_file> I<filename> B<-result_file> I<filename> [B<-asfp_min_tm> I<int>] [B<-asfp_opt_tm> I<int>] [B<-asfp_max_tm> I<int>] [B<-lsrp_min_tm> I<int>] [B<-lsrp_opt_tm> I<int>] [B<-lsrp_max_tm> I<int>] [B<-min_primer_length> I<int>] [B<-max_primer_length> I<int>] [B<-self_comp_any> I<int>] [B<-self_comp_end> I<int>] [B<-product_size> I<range>] [I<-help>] [I<-man>]

=head1 DESCRIPTION

SNP-SCALE Primer Designer is a command line program which utilises Primer3 (Rozen & Skaletsky 2000) for calculating properties of allele-specific forward primers and for finding suitable matching locus-specific reverse primers.

=head1 QUICK START USERS GUIDE

=over

=item 1.

Firstly, ensure your computer meets the L<"requirements"> for running SNP-SCALE Primer Designer.

=item 2.

Download the latest version of SNP-SCALE Primer Designer from L<http://www.sheffield.ac.uk/molecol/software~/snp.html> and uncompress it anywhere on your computer.

=item 3.

Open a command-prompt.

In MS Windows, click B<Start> >> B<Run> and type C<cmd> and click B<OK>

=item 4.

At the command prompt, move to the directory where you uncompressed SNP-SCALE Primer Designer by typing for example:

C<cd C:\SNP-SCALE_Primer_Designer_v0.1.0>

=item 5.

At the command prompt, display the SNP-SCALE Primer Designer help text by typing:

C<perl snp-scale_pd.pl -help>

=item 6.

To run SNP-SCALE Primer Designer, you need to specify at the very minimum, an input file (B<-infile>), an output summary file (B<-summary_file>) and an output report file (B<-report_file>). For example:

C<perl snp-scale_pd.pl -infile myinputfile -summary_file summary.csv -report_file report.txt>

=back

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the entire manual page and exits.

=item B<-infile> I<string>

B<REQUIRED>

Input file containing sequence data and allele information. The currently accepted file format is a modified version of FASTA format, whereby polymorphisms and their alleles are represented as [I<allele1>/I<allele2>/I<allele3>] within the sequence data. In SNP-SCALE Primer Designer, nucleotides are case insensitive. Use of upper/lowercase nucleotides in the below example are for visual clarity and ease at which to identify polymorphisms.

Example input file could contain:

>seq1
ctgtgcaatgatcactaacattgggctggtaattgcgttgtt[G/C]agtgta[A/C]atttccgggtttat
>seq2
gtcttcttcttctcctcgaattgggtttttcttagctgaacctcctc[*/CTT]atcatttgtctctgtggag[G/A]ttttatttgccagtctcctcaacagaaacagt
>gs054F(480-820)
aaattaagagagactgcatgctaccttctgaatatcttc[C/T][A/C]aaagcagtcaattcttagagcacgttcaagcagctctatcggagtctaagaa

We aim to move towards the use of a standard input file format that is capable of describing polymorphisms inherently. We would be happy to get feedback from the community with regards to what input file formats we should support.

=item B<-summary_file> I<string>

B<REQUIRED>

Output file containing summary information. This file is a tab-delimited plain text file containing summary information about the number of allele-specific forward primers assessed for each allele on each stand and the number of allele-specific forward primers which have at least 1 suitable locus-specific reverse primer.

=item B<-result_file> I<string>

B<REQUIRED>

Output file containing the Primer3 results for all allele-specific forward primers with 1 or more locus-specific reverse primer.

=item B<-asfp_min_tm> I<integer>

I<DEFAULT=55>

Allele-specific forward primer minimum Tm.

=item B<-asfp_opt_tm> I<integer>

I<DEFAULT=60>

Allele-specific forward primer optimum Tm.

=item B<-asfp_max_tm> I<integer>

I<DEFAULT=65>

Allele-specific forward primer maximum Tm.

=item B<-lsrp_min_tm> I<integer>

I<DEFAULT=60>

B<Does not currently affect anything.>

Locus-specific reverse primer minimum Tm.

=item B<-lsrp_opt_tm> I<integer>

I<DEFAULT=65>

Locus-specific reverse primer optimum Tm.

=item B<-lsrp_max_tm> I<integer>

I<DEFAULT=70>

Locus-specific reverse primer maximum Tm.

=item B<-min_primer_length> I<integer>

I<DEFAULT=18>

Minimum primer length in number of nucleotides.

=item B<-max_primer_length> I<integer>

I<DEFAULT=36>

Maximum primer length in number of nucleotides.

=item B<-self_comp_any> I<integer>

I<DEFAULT=8>

Maximum primer self complementarity at ANY position

=item B<-self_comp_end> I<integer>

I<DEFAULT=6>

Maximum primer self complementarity at the 3' END

=item B<-product_size> I<string>

I<DEFAULT=36-350>

Required product size. This should be entered as a space separated list of ranges, for example:

-product_size "150-250 100-300 301-400"

=back

=head1 REQUIREMENTS

The following minimum requirements need to be met in order to run SNP-SCALE Primer Designer. Feel free to contact the author of this software if you require help or clarification.

=over 8

=item B<Operating System>

SNP-SCALE Primer Designer will work on any OS for which Primer3 and a Perl interpreter is available (see below)

=item B<Primer3>

SNP-SCALE Primer Designer harnesses the power of Primer3 to calculate properties of allele-specific forward primers and find suitable locus-specific reverse primers. Primer3 can be obtained from: L<http://sourceforge.net/projects/primer3/>

=item B<Perl>

A Perl interpreter is required to run SNP-SCALE Primer Designer. These are available for most operating systems (OS) and are usually installed by default on UNIX/Linux based OS's. For MS Windows, you should install the latest version of Perl from ActiveState: L<http://aspn.activestate.com/ASPN/Downloads/ActivePerl/>

=item B<Perl Modules>

The following Perl modules are required and can be found in the CPAN if they are not already installed with the Perl interpreter.

=over

=item 1.

Getopt::Long

=item 2.

Pod::Usage

=back

=back

=head1 HOW TO CITE

If you utilise SNP-SCALE Primer Designer and/or the Multiplex SNP-SCALE methodology, please use the following citation:

T. Kenta, J. Gratten, N. S. Haigh, G. N. Hinten, J. Slate, R. K. Butlin and T. Burke (submitted) Multiplex SNP-SCALE: a cost-effective medium-throughput SNP genotyping method. I<Molecular Ecology Notes>.

=head1 BUGS/CAVEATS

=over

=item Indels

SNP-SCALE Primer Designer will not handle indel type polymorphisms. We aim to rectify this in a later release.

=item Input File Formats

SNP-SCALE Primer Designer utilises a non-standard sequence file format as input. This was born out of the fact that it was the easiest/quickest way to add such information from the tools being used (consed) for sequence assembly and SNP detection. We aim to add support for more appropriate and standard sequence formats that natively support the inclusion of polymorphism information in a later release. However, we would greatly appreciate feedback with regards to what sequence file formats we should support.

=item Result File

SNP-SCALE Primer Designer outputs Primer3 results data for all ASFP's with 1 or more LSRP. This information is not the easiest document to view and pick out primers by eye. We aim to provide a means by which this information may be made more accessible in a later release.

=item Memory Usage

SNP-SCALE Primer Designer currently reads all the input sequences into memory before proceeding. Thus, SNP-SCALE Primer Designer may not scale well to a large/very large input file.

=back

=head1 REFERENCES

=over 8

=item B<Primer3>

Rozen S, Skaletsky H (2000) Primer3 on the WWW for general users and for biologist programmers. In: Krawetz S, Misener S (eds) Bioinformatics Methods and Protocols: Methods in Molecular Biology. Humana Press, Totowa, NJ, pp 365-386.

L<http://jura.wi.mit.edu/rozen/papers/rozen-and-skaletsky-2000-primer3.pdf>

=back

=head1 COPYRIGHT

SNP-SCALE Primer Designer is copyrighted under the same terms as Perl itself. A copy of the I<Perl Artistic License> is provided below.

Copyright 2008 Nathan S. Haigh <bioinf@watsonhaigh.net>.

=head2 Preamble

The intent of this document is to state the conditions under which a
Package may be copied, such that the Copyright Holder maintains some
semblance of artistic control over the development of the package,
while giving the users of the package the right to use and distribute
the Package in a more-or-less customary fashion, plus the right to make
reasonable modifications.

=head2 Definitions

=over

=item "Package"

refers to the collection of files distributed by the
Copyright Holder, and derivatives of that collection of files created
through textual modification.

=item "Standard Version"

refers to such a Package if it has not been
modified, or has been modified in accordance with the wishes of the
Copyright Holder as specified below.

=item "Copyright Holder"

is whoever is named in the copyright or
copyrights for the package.

=item "You"

is you, if you're thinking about copying or distributing this Package.

=item "Reasonable copying fee"

is whatever you can justify on the basis
of media cost, duplication charges, time of people involved, and so on.
(You will not be required to justify it to the Copyright Holder, but
only to the computing community at large as a market that must bear the
fee.)

=item "Freely Available"

means that no fee is charged for the item
itself, though there may be fees involved in handling the item. It also
means that recipients of the item may redistribute it under the same
conditions they received it.

=back

=head2 Conditions

=over

=item 1.

You may make and give away verbatim copies of the source form of the
Standard Version of this Package without restriction, provided that you
duplicate all of the original copyright notices and associated disclaimers.

=item 2.

You may apply bug fixes, portability fixes and other modifications
derived from the Public Domain or from the Copyright Holder.  A Package
modified in such a way shall still be considered the Standard Version.

=item 3.

You may otherwise modify your copy of this Package in any way, provided
that you insert a prominent notice in each changed file stating how and
when you changed that file, and provided that you do at least ONE of the
following:

=over

=item a)

place your modifications in the Public Domain or otherwise make them
Freely Available, such as by posting said modifications to Usenet or an
equivalent medium, or placing the modifications on a major archive site
such as uunet.uu.net, or by allowing the Copyright Holder to include
your modifications in the Standard Version of the Package.

=item b)

use the modified Package only within your corporation or organization.

=item c)

rename any non-standard executables so the names do not conflict with
standard executables, which must also be provided, and provide a
separate manual page for each non-standard executable that clearly
documents how it differs from the Standard Version.

=item d)

make other distribution arrangements with the Copyright Holder.

=back

=item 4.

You may distribute the programs of this Package in object code or
executable form, provided that you do at least ONE of the following:

=over

=item a)

distribute a Standard Version of the executables and library files,
together with instructions (in the manual page or equivalent) on where
to get the Standard Version.

=item b)

accompany the distribution with the machine-readable source of the
Package with your modifications.

=item c)

give non-standard executables non-standard names, and clearly
document the differences in manual pages (or equivalent), together with
instructions on where to get the Standard Version.

=item d)

make other distribution arrangements with the Copyright Holder.

=back

=item 5.

You may charge a reasonable copying fee for any distribution of this
Package.  You may charge any fee you choose for support of this
Package.  You may not charge a fee for this Package itself.  However,
you may distribute this Package in aggregate with other (possibly
commercial) programs as part of a larger (possibly commercial) software
distribution provided that you do not advertise this Package as a
product of your own.  You may embed this Package's interpreter within
an executable of yours (by linking); this shall be construed as a mere
form of aggregation, provided that the complete Standard Version of the
interpreter is so embedded.

=item 6.

The scripts and library files supplied as input to or produced as
output from the programs of this Package do not automatically fall
under the copyright of this Package, but belong to whoever generated
them, and may be sold commercially, and may be aggregated with this
Package.  If such scripts or library files are aggregated with this
Package via the so-called "undump" or "unexec" methods of producing a
binary executable image, then distribution of such an image shall
neither be construed as a distribution of this Package nor shall it
fall under the restrictions of Paragraphs 3 and 4, provided that you do
not represent such an executable image as a Standard Version of this
Package.

=item 7.

C subroutines (or comparably compiled subroutines in other
languages) supplied by you and linked into this Package in order to
emulate subroutines and variables of the language defined by this
Package shall not be considered part of this Package, but are the
equivalent of input as in Paragraph 6, provided these subroutines do
not change the language in any way that would cause it to fail the
regression tests for the language.

=item 8.

Aggregation of this Package with a commercial distribution is always
permitted provided that the use of this Package is embedded; that is,
when no overt attempt is made to make this Package's interfaces visible
to the end user of the commercial distribution.  Such use shall not be
construed as a distribution of this Package.

=item 9.

The name of the Copyright Holder may not be used to endorse or promote
products derived from this software without specific prior written permission.


=item 10.

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

=back

The End

=cut


=cut
