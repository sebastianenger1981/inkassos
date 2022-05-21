#! /usr/bin/perl

#
# Author: Sebastian Enger, M.Sc.
# Date: 4/12/2016
# Website: www.OneTIPP.com
# Topic: Server Manager is creating training tasks in on https://tech.onetipp.net/task.php for Client Slaves
# Version: 0.1.8
#
use strict;
use DBI;
use DBD::mysql;
use Crypt::Digest::SHA512;
use Digest::MD5 qw(md5 md5_hex md5_base64);
#  use Hash::Ordered;
use LWP::UserAgent; 

#use IPC::Run qw( start pump finish timeout run);
use Data::Dumper;
use Lingua::DE::Wortschatz ':all'; 
#use Lingua::EN::Fathom;
#use Lingua::Sentence;
use Text::ParseWords;
#use MongoDB;
#use MongoDB::OID;
use Mango;

use Encode qw/from_to/;
use Encode::Encoder qw(encoder);

use constant VERSION 	=> "0.1.7";

# http://search.cpan.org/dist/WordNet-Similarity/
# http://search.cpan.org/~burak/Lingua-Any-Numbers-0.45/lib/Lingua/Any/Numbers.pm
# http://search.cpan.org/dist/MongoDB/lib/MongoDB/Tutorial.pod
# http://www.s-anand.net/blog/splitting-a-sentence-into-words/

#my $splitter 			= Lingua::Sentence->new("de");
my $sha512 				= Crypt::Digest::SHA512->new();
#my $mongo 				= MongoDB::MongoClient->new();

my $mango 				= Mango->new('mongodb://localhost:27017');
my $mongo   			= $mango->db('servermanagement')->collection('traintexts');

#my $db 					= $mongo->get_database('servermanagement');
#my $trainDB				= $db->get_collection('traintexts');

#DATA SOURCE NAME
my $dsn 				= "dbi:mysql:onetipp:localhost:3306";

my $treetagger			= "/home/Framework/ServerManager/library/cmd/tree-tagger-german";
my $InstallFile 		= "/home/Framework/DemoParser/versicherung.txt";	# file with textcontent to process
my $TempCorpus  		= "/tmp/temp_corpus";
my $NounSentencer		= "/home/Framework/ServerManager/modules/nounsentences.py";
my $ReadabilityCalc		= "/home/Framework/ServerManager/modules/readability.py";
my $wordCount 			= 182;	# Words per trainingscorpus: 182 X 3 (1x original Text + 2 Text copy with Synonyms) = ~ 550 Wörter bei RNN 512 mit Grafikkartenserver
my $trainTime			= "3h";	#h,m,d for each task -> this is the time the client should run this task: hours, minutes, days
my $SynChangePosTags	= "(NN|ADJD)"; # (NN|ADJD)
my $WortschatzTimeout	= 15;
#my $WortschatzMonitorFlag = 0;
my $TrainingstextLanguage = "DEU"; # later generate automatically


sub numerically {$b <=> $a};

&chunkText($InstallFile);

sub chunkText(){
	my $in = shift;
	
	my $data;
	{
		open my $fh, '<:encoding(UTF-8)', $in or die;
		binmode($fh);
		local $/ = undef;
		$data = <$fh>;
		close $fh;
	}
	
	my %tmp 				= ();
	my $tmp 				= {};
	my %syn 				= ();
	my $syn 				= {};
	my $c 					= 0;
	my $c_tmp 				= 0;
	my $tmp_word			= "";
	my $result1				= "";
	my @lines 				= ();
	my $result_word			= "";
	my $freq_word			= "";
	my $class_word			= "";
	my $result3				= "";
	my $freq				= "";
	my $class				= "";
	my $word				= "";
	my $postag				= "";
	my $s					= "";
	
	my %all_results 		= ();
	my $all_results 		= {};
	my %tmp_store 			= ();
	my $tmp_store 			= {};
	my $all_result_count 	= 0;
	my $tmp_store_flag 		= 0;
	
	my %wordCalc 			= ();
	my $wordCalc 			= {};
	my @final1_sent			= ();
	my @final2_sent			= ();
	my @final3_sent			= ();
	my @original_sent		= ();
	my $wordOrg				= "";
	my $posTag				= "";
	my @tagged_text			= ();
	my $rText				= "";
	my $traintext			= "";
	my $orginaltext			= "";
	my $created				= "";
	my $hash				= "";
	my $readability			= 0;
	
	# debug:
	#	my $chars = substr ($data, 0, 1000);
	#	#print Dumper $chars; exit;
	#	#my @words = split(/ /, $data, $textcount);
	#	#my @words 	= split(/(\s)+(\w)+(\s)?(\.|\!|\?)?/i, $chars);
	my @words 	= split(" ", $data);
	my @array_p = ();

	while (scalar(@words)>=1){
		
		# Go for Safety -> delete all variabels that are used during this While-Loop
		%tmp 				= ();
		$tmp 				= {};
		%syn 				= ();
		$syn 				= {};
		$c 					= 0;
		$c_tmp 				= 0;
		$tmp_word			= "";
		$result1			= "";
		@lines 				= ();
		$result_word		= "";
		$freq_word			= "";
		$class_word			= "";
		$result3			= "";
		$freq				= "";
		$class				= "";
		$word				= "";
		$postag				= "";
		$s					= "";
		
		%all_results 		= ();
		$all_results 		= {};
		%tmp_store 			= ();
		$tmp_store 			= {};
		$all_result_count 	= 0;
		$tmp_store_flag 	= 0;
		
		%wordCalc 			= ();
		$wordCalc 			= {};
		@final1_sent		= ();
		@final2_sent		= ();
		@final3_sent		= ();
		@original_sent		= ();
		$wordOrg			= "";
		$posTag				= "";
		@tagged_text		= ();
		$rText				= "";
		$traintext			= "";
		$orginaltext		= "";
		$created			= "";
		$hash				= "";
		
		print "1.: Splitting Sentences to Words\n";
		my @t 			= splice(@words, 0, $wordCount-1);
				
		$traintext 		= join(" ", @t);
		$orginaltext 	= $traintext;
		$created 		= time();
		$sha512->add($traintext.$created);
		$hash 			= $sha512->hexdigest;
		
		# delete temporary train corpus
		unlink $TempCorpus;
		
		print "1.1: Writing temporary Text Corpus to File\n";
		open(W,">$TempCorpus");
			binmode(W);
			print W $traintext;
		close W;
		
		#my $result3=Lingua::DE::Wortschatz::use_service('Frequencies',"Auto");
		#print Dumper $result3;
	
		print "2.: Doing NounSentencer Chunker\n";
		# do NounSentence Chunker
		$rText 			= `python3 $NounSentencer -i $TempCorpus 2>/dev/null`;
		
		print "3.: POS Tagging using Tree Tagger for Sentences\n";
		# POS Tagging using Tree Tagger
		my $rTagged 	= `perl $treetagger $TempCorpus 2>/dev/null`;		
				
		@tagged_text 	= split("\n", $rTagged);
		
		print "4.: Foreach Pos Tagged Word\n";
		foreach my $t (@tagged_text){
			if ($c == 0){	# We dont need first line of TreeTagger output
				$c++;
				next;
			};
			($word,$postag,undef) = split(/\s{1,}/,$t);
			#print "$word,$postag\n";
			#if ($postag =~ m/(NN|ADJD)/ig){
			next if ($postag !~ m/$SynChangePosTags/ig);
			$tmp_word 	= $word;
			$tmp_word 	=~ s/(\.|\!|\?|\,|\;|\:)//g;	# remove sentence delimiter -> this $var later goes to Syn & Freq Check of Uni Leipzig
			
			#	1. Synonym erfragen
			#	2. Frequencies berechnen
			#	3. synonyme mit meisten frequencies benutzen
			
			print "5.: Query Wortschatz Leipzig for Synonyms\n";
			#print "In postag funktion: $postag\n";
			#my $result1	= Lingua::DE::Wortschatz::use_service('Thesaurus',$word,7);
			
			RESTARTSYNONYMS:
				# Check if WortschatzLeipzig is online
				for(my $i = 0; $i > 1; $i--) {	# try forever
					my $WortschatzMonitorFlag = 0;
					$WortschatzMonitorFlag = &WortschatzServiceMonitor();
					if($WortschatzMonitorFlag == 1) { last; }  # for-Schleife abbrechen
					print "Uni Leipzig down: Waiting $WortschatzTimeout seconds -> Query for Synonyms()\n"; 
					sleep $WortschatzTimeout;
				} # for(my $i = 0; $i > 1; $i--) {
					
			eval{
				$result1	= Lingua::DE::Wortschatz::use_service('Synonyms',$tmp_word);
				@lines 		= $result1->hashrefs();
			};
			if($@) { 
				print "Fehler: -> Bei Query for Synonyms()\n"; 
				goto RESTARTSYNONYMS;
			}
			
			%tmp_store = {};
			$tmp_store = {};
	
			RESTARTSINGLEWORDFREQUENCIES:
				# Check if WortschatzLeipzig is online
				for(my $i = 0; $i > 1; $i--) {
					my $WortschatzMonitorFlag = 0;
					$WortschatzMonitorFlag = &WortschatzServiceMonitor();
					if($WortschatzMonitorFlag == 1) { last; }  # for-Schleife abbrechen
					print "Uni Leipzig down: Waiting $WortschatzTimeout seconds -> Query for Frequencies()\n";  
					sleep $WortschatzTimeout;
				} # for(my $i = 0; $i > 1; $i--) {
			
			print "5.1: Query Wortschatz Leipzig for Frequencies (tmp_word)\n";
	
			eval{
				$result_word	= Lingua::DE::Wortschatz::use_service('Frequencies',$tmp_word);
				$freq_word		= $result_word->{"data"}[0][0];
				$class_word 	= $result_word->{"data"}[0][1];
			};
			if($@) { 
				print "Fehler: $@ -> Bei Query for Frequencies()\n"; 
				goto RESTARTSINGLEWORDFREQUENCIES;
			}
							
			#
			## Foreach found synonym
			#			
			foreach my $l (@lines) {
				$s = $l->{Synonym};
				next if (length($s)<3);	# Synonym must have string lenght of at least 3 char
				#print "Frequency Check for Synonym: $s\n";
				
				RESTARTCHECKSYNONYMFREQUENCIES:
					# Check if WortschatzLeipzig is online
					for(my $i = 0; $i > 1; $i--) {
						my $WortschatzMonitorFlag = 0;
						$WortschatzMonitorFlag = &WortschatzServiceMonitor();
						if($WortschatzMonitorFlag == 1) { last; }  # for-Schleife abbrechen
						print "Uni Leipzig down: Waiting $WortschatzTimeout seconds -> Query for Frequencies( of Synonyms )\n";  
						sleep $WortschatzTimeout;
					} # for(my $i = 0; $i > 1; $i--) {
					
				eval{
					$result3	= Lingua::DE::Wortschatz::use_service('Frequencies',$s);
					$freq 		= $result3->{"data"}[0][0];
					$class 		= $result3->{"data"}[0][1];
				};
				if($@) { 
					print "Fehler: $@ -> Bei Query for Frequencies( of Synonyms )\n"; 
					goto RESTARTCHECKSYNONYMFREQUENCIES;
				}
			
				#
				# We only want synomyms of the same class
				#
				next if ($class != $class_word);
				
				#print "(w):$word <-> (s): $s ====> (wc): $class_word und (sc): $class\n";exit;
				
				my %tttmp = ();
				my $tttmp = {};
				
				if (length($word)>=2 && length($s)>=2 && length($freq)>=1){
					from_to($word,"latin1","utf8");
					from_to($s,"latin1","utf8");
					$tttmp->{"word"} = $word;
					$tttmp->{"syn"} = $s;
					$tttmp->{"freq"} = $freq;
									
					if (!exists($tmp_store{$freq})){ #freq not exists
						$tmp_store->{$freq} = $tttmp;
						$tmp_store_flag++;
					} else { #freq exists
						my $range = 20;
						my $rand = int(rand($range));
						$tmp_store->{$freq+$rand} = $tttmp;
						$tmp_store_flag++;
					} # if (!exists($tmp_store{$freq})){
				} # if (length($word)>=2 && length($s)>=2 && length($freq)>=1){
			#	my $md5 = md5_hex($word.$s.$freq);
			#	$tmp_store->{$md5} = $tttmp;
				#$all_results->{$md5} = $tttmp;
				$c_tmp++;
			} # foreach synonym
			
		#	my $md5_ts = md5_hex($tmp_store.keys(%{$tmp_store}).values(%{$tmp_store}).time());
		#	$all_results->{$md5_ts} = $tmp_store;	
		#	$c++;
			if ( $tmp_store_flag > 0){
				$all_results->{$all_result_count} = $tmp_store;	
				$all_result_count++;
				$tmp_store_flag = 0;
			}
		} # foreach tagged text
		
		print "6.: Exchanging Synonyms in Original Text Corpus\n";
				
		foreach my $t2 (@tagged_text){
			if ($c == 0){ # We dont need first line of TreeTagger content
				$c++;
				next;
			};
			
			($wordOrg,$posTag,undef) = split(/\s{1,}/,$t2);
			push(@original_sent, $wordOrg);
			if ($posTag =~ m/$SynChangePosTags/ig){
				
				my $changeFlag1 = 0;
				my $changeFlag2 = 0;
				my $changeFlag3 = 0;
				
				#
				# Create the same content with three different Synonyms each -> give RNN more variables to change the text & plus the original content
				#
				foreach my $cycle (keys %{$all_results}) {
					foreach my $key (sort numerically keys(%{$all_results->{$cycle}})) {
						my $hashWord 	= $all_results->{$cycle}->{$key}->{word};
						my $hashSyn 	= $all_results->{$cycle}->{$key}->{syn};
						if ($wordOrg eq $hashWord && !exists($wordCalc{$hashSyn})){
							
							#
							# if $changeFlagX sequence is important
							#
							
							if ($changeFlag2==1){
							#	print "{$key}: Change3 ($wordOrg) with [$hashSyn]\n";
								$wordCalc{$hashSyn} = $hashSyn;
								#push(@final3_sent, "<b>$hashSyn</b>");
								push(@final3_sent, $hashSyn);
								$changeFlag3 = 1;
							}  elsif ($changeFlag1==1){
							#	print "{$key}: Change2 ($wordOrg) with [$hashSyn]\n";
								$wordCalc{$hashSyn} = $hashSyn;
								#push(@final2_sent, "<b>$hashSyn</b>");
								push(@final2_sent, $hashSyn);
								$changeFlag2 = 1;
							} elsif ($changeFlag1==0){
							#	print "{$key}: Change1 ($wordOrg) with [$hashSyn]\n";
								$wordCalc{$hashSyn} = $hashSyn;
								#push(@final1_sent, "<b>$hashSyn</b>");
								push(@final1_sent, $hashSyn);
								$changeFlag1 = 1;	
							} # if ($changeFlag2==1){
						} # if ($wordOrg eq $hashWord && !exists($wordCalc{$hashSyn})){
					} # foreach my $key (sort numerically keys(%{$all_results->{$cycle}})) {
				} # foreach my $cycle (keys %{$all_results}) {
							
				if ($changeFlag1 == 0){
					push(@final1_sent, $wordOrg);
				}
				if ($changeFlag2 == 0){
					push(@final2_sent, $wordOrg);
				}
				if ($changeFlag3 == 0){
					push(@final3_sent, $wordOrg);
				}
			} else {
				push(@final1_sent, $wordOrg);
				push(@final2_sent, $wordOrg);
				push(@final3_sent, $wordOrg);
			} #if ($posTag =~ m/$SynChangePosTags/ig){
		} # foreach my $t2 (@tagged_text){
	
	
		print "6.1: Merge Synonym Text and Orignal Text\n";
		
		my $org_text 		= join(" ", @original_sent);
		my $new1_text 		= join(" ", @final1_sent);
		my $new2_text 		= join(" ", @final2_sent);
		my $new3_text 		= join(" ", @final3_sent);
		my $trainTextNew	= $org_text ."\n". $new1_text ."\n". $new2_text ."\n". $new3_text;
		
	#	from_to($trainTextNew,"latin1","utf8");
	#	from_to($orginaltext,"latin1","utf8");
	#	from_to($rText,"latin1","utf8");
		
	#	print "Original: $org_text\n#########\n";
	#	print "Kopie1: $new1_text\n#########\n";
	#	print "Kopie2: $new2_text\n#########\n";
	#	print "Kopie3: $new3_text\n#########\n";
		
		# delete temporary train corpus
		unlink $TempCorpus;
		
		print "6.9.1: Writing temporary new created trainText with Syn Exchange to File\n";
		open(W,">$TempCorpus");
			binmode(W);
			print W $trainTextNew;
		close W;
		
		print "6.9.2.: Calculating Readability (Flesch Reading Ease)\n";
		$readability = `python $ReadabilityCalc -i $TempCorpus 2>/dev/null`;
		chomp($readability);
		print "6.9.3.: Calculating Readability Value: $readability\n";

	#	* 90-100 : Very Easy 
	#	* 80-89 : Easy 
	#	* 70-79 : Fairly Easy 
	#	* 60-69 : Standard 
	#	* 50-59 : Fairly Difficult 
	#	* 30-49 : Difficult 
	#	* 0-29 : Very Confusing

		print "7.: Writing Info to Mysql Database\n";
		
		# set the value of your SQL query
		#my $query = "INSERT INTO servermanagement (id, meta, orginaltext, traintext, hash, created, done, outdated, worktime) values ('', $rText, $orginaltext, $trainTextNew, $hash, $created, 0, 0, $trainTime)";

		# PERL DBI CONNECT
		my $dbh = DBI->connect($dsn, "root", "rouTer99", {RaiseError => 0, PrintError => 1,mysql_enable_utf8 => 1} ) or warn "Unable to connect: $DBIconnect::errstr\n";

		my $query = sprintf("%s (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
			"INSERT INTO servermanagement (id, meta, orginaltext, traintext, hash, created, done, outdated, status, worktime, lang, readability) VALUES",
			$dbh->quote(""),
			$dbh->quote($rText),
			$dbh->quote($orginaltext),
			$dbh->quote($trainTextNew),
			$dbh->quote($hash),
			$dbh->quote($created),
			$dbh->quote(0),
			$dbh->quote(0),
			$dbh->quote(0),
			$dbh->quote($trainTime),		
			$dbh->quote($TrainingstextLanguage),
			$dbh->quote($readability)
		);
		
		# prepare your statement for connecting to the database
		my $sth = $dbh->prepare($query);

		$sth->execute();# or warn $DBI::errstr;
		$sth->finish();
		$dbh->commit;# or warn $DBI::errstr;
		
		print "7.1: Writing Info to MongoDB Database\n";
		$mongo->insert({
					"meta" 			=> $rText,
					"orginaltext" 	=> $orginaltext,
					"traintext" 	=> $trainTextNew,
					"hash"			=> $hash,
					"created"		=> $created,
					"done"			=> 0,
					"outdated"		=> 0,
					"status"		=> 0,
					"worktime"		=> $trainTime,
					"lang"			=> $TrainingstextLanguage,
					"readability"	=> $readability,
				});	
		print "8: Writing Info Database (Mysql & MongoDB) finished -> Sleeping 5 seconds\n";
		sleep 5;
	} #while (scalar(@words)>=1){
} # sub chunkText(){


sub wordSplitter(){
	my $in = shift;

# Split by clear word separators
my $regex = /[\s \! \? \;\(\)\[\]\{\}\<\> " ]
# ... by COMMA, unless it has numbers on both sides: 3,000,000
|(?<=\D) ,
|, (?=\D)
 
# ... by FULL-STOP, SINGLE-QUOTE, HYPHEN, AMPERSAND, unless it has a letter on both sides
|(?<=\W) [\.\-\&]
|[\.\-\&] (?=\W)
 
# ... by QUOTE, unless it follows a letter (e.g. McDonald's, Holmes')
|(?<=\W) [']
 
# ... by SLASH, if it has spaces on at least one side. (URLs shouldn't be split)
|\s \/
|\/ \s
 
# ... by COLON, unless it_s a URL or a time (11:30am for e.g.)
|\:(?!\/\/|\d)
/x;
my @words = $in =~ $regex;
print Dumper @words;
}

sub WortschatzServiceMonitor(){
	my $url = 'http://anonymous:anonymous@pcai055.informatik.uni-leipzig.de:8100/axis/services/ServiceOverview?wsdl';

	my $ua = LWP::UserAgent->new( max_redirect => 0, env_proxy => 0,keep_alive => 1, timeout => 3, agent => "OneTIPP (Service Alive Check)/0.0.1");
	my $response = $ua->head($url);
	if ($response->code == 200){
		return 1;
	} else {
		return 0;
	}
	return 0;
}


sub cpu_count(){
	my $cpu_count = 32;
	open CPU, "/proc/cpuinfo" or warn "Can't open cpuinfo\n";
		#printf "CPUs: %d\n", scalar (map /^processor/, <CPU>) ; 
		$cpu_count = scalar (map /^processor/, <CPU>);
	close CPU;
	
	return $cpu_count;
} # sub cpu_count(){