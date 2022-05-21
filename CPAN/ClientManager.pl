#! /usr/bin/perl

#
# Author: Sebastian Enger, M.Sc.
# Date: 4/17/2016
# Website: www.OneTIPP.com
# Topic: Client Manager is getting work task from https://tech.onetipp.net/task.php for processing in Docker Image
# Version: 0.1.8
# UPDATE `servermanagement` SET `done`= "0" WHERE `done` = 1
###system("clear");

use strict;
use utf8;   # wichtig;
use sigtrap qw(die untrapped normal-signals stack-trace any error-signals);
use Crypt::Digest::SHA512;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use LWP::UserAgent; 
use HTTP::Request::Common;

use Data::Dumper;
use Tie::File::AsHash;
use XML::Simple;
use Proc::Background;
use File::Path 'make_path';
use File::Basename;
use File::Copy;
use Cwd 'abs_path';
 
use HTML::Entities;
use Parallel::ForkManager;
use Term::ProgressBar; 
 
use constant HOME 			=> "https://tech.onetipp.net/task.php";
use constant VERSION 		=> "0.1.8";
use constant UPDATETIME 	=> 900; # max run each update process 15 minutes
use constant SCRIPT 		=> abs_path($0);
use constant MAX_PROCESSES 	=> 1;

use constant TRAIN 			=> "/var/tmp/onetipp/train.py";
use constant SAMPLE 		=> "/var/tmp/onetipp/sample.py";
use constant LIBRARY		=> "/var/tmp/onetipp/CharRNN.py";

use constant HOME_DIR		=> "/var/tmp/onetipp";
use constant DEEP_CV		=> "/var/tmp/onetipp/cv";
use constant DEEP_DATA		=> "/var/tmp/onetipp/data";
use constant TMP			=> "/var/tmp";

my $fs 	= HOME_DIR;
system("rm -rf $fs"); # Debug

my $ConfigHash				= ();
my %ConfigHash				= {};

my $TimeHash				= ();
my %TimeHash				= {};
$TimeHash->{"s"} 			= 1;
$TimeHash->{"m"} 			= 60;
$TimeHash->{"h"} 			= 3600;
$TimeHash->{"d"} 			= 24*3600;

my $xml 					= XML::Simple->new( StrictMode => 0 );
my $dig 					= Digest::MD5->new();

# Step 0: Init
&init();

RESTART:

# Step 1: Get $HOME 
my $starturl				= HOME;
my $StartXML 				= &getWebContent($starturl);

# Step 2: Parse $HOME XML
my ($h,$q,$k) 				= &parseStartXML($StartXML);

# Step 3: Make Docker Image Internal Software Update
#&ForceInternalDockerImageAPTUpdate($q);

# Step 4: Make Deep Learning Software Update
&DeepLearningTrainingSoftwareUpdate($k);

# Step 5: Make ClientManager Update
#&ForceClientManagerUpdate($h);

# Step 6: Get New Task
my $hash 					= &getTask();

# Step 6.1: Processing & Send results
my $rFlag 					= &processTask($hash);

goto RESTART;
exit;

sub processTask(){
	my $hashpT	 	= shift;
	my $gpu_status 	= `nvidia-smi -L 2>/dev/null`;
	my $gpu 		= "";
	
	my $python_script 	= $hashpT->{'send_train'};
	my $data_dir 		= $hashpT->{'data'};
	my $checkpoint_dir 	= $hashpT->{'cv'};
	my $runtime 		= $hashpT->{'runtime'};
	
	if ($gpu_status =~ /fail/ig){
		# only cpu available
		$gpu = -1;	# must be set to -1 for chainer to use cpu
	} elsif ($gpu_status =~ /gpu/ig){
		#gpu available
		$gpu = 0; # must be set to 0 for chainer to use first gpu
	}
	
	#print "{EXECUTE} python $python_script --data_dir $data_dir --checkpoint_dir $checkpoint_dir --gpu $gpu\n";

	my $start_time 	= time();
	my $cmd 		= "python $python_script --data_dir $data_dir --checkpoint_dir $checkpoint_dir --gpu $gpu >/dev/null 2>1";
	my $check_time 	= $start_time + (5*60);

	#my $n = MAX_PROCESSES;
	my $n = 1;
	my $forks = 0;
	for (1 .. $n) {
	  my $pid = fork;
	  if (not defined $pid) {
		 warn 'Could not fork';
		 next;
	  }
	  if ($pid) {
		$forks++;
		print "In the parent process PID ($$), Child pid: $pid Num of fork child processes: $forks\n";
	  } else {
		print "In the child process PID ($$)\n"; 
		system($cmd);
		#sleep $runtime;
		#my $flag = &sendTask($hashpT);
		print "Child ($$) exiting\n";
		#exit;
	
		#print "$cmd\n";
		#print "Child ($$) exiting";
		#exit;
	  }
	}
	 
#	for (1 .. $forks) {
#	   my $pid = wait();
#	  print "Parent saw $pid exiting\n";
#	}
	
	while (1){
		sleep 10;
		my $tc = time();	
		# Upload results every 5 minutes
		if ($check_time >= $tc){
			print "*** Five Minutes Over: Sending Results: \n";
			# Step 7: SendTask - try 15 times
			for(my $i = 0; $i <= 15; $i++) {
				my $flag = &sendTask($hashpT);
				if ($flag == 1){
					last;
				}
			} # for(my $i = 0; $i > 1; $i--) {
			$check_time += (5*60);
		} # if ($check_time >= $tc){
		
		if ($tc >= $start_time+$runtime){
			print "*** Training Time is Over: Sending Results: \n";
			# Step 7: SendTask - try 15 times
			for(my $i = 0; $i <= 15; $i++) {
				my $flag = &sendTask($hashpT);
				if ($flag == 1){
					last;
				}
			} # for(my $i = 0; $i > 1; $i--) {
			#my $pid = wait();
			system("kill -9 `pidof python`");
			#system("kill -9 $$");
			print "Ending Call\n";
			exit;
		} #if ($start_time+$runtime >= $tc){
	} # while (1){
	return 1;
} # sub processTask(){

sub sendTask(){
	my $ConfigHash 	= shift;
	my $aid 		= $ConfigHash->{"aid"};
	my $starturl	= HOME;
	my $v 			= VERSION;
	my $seconds 	= UPDATETIME;
	my $url			= $starturl;# ."?action=sendTask";			
	
	print "sendTask(): Sending content to tech.onetipp.net\n";
	my $r;
	my $rnd;
	open $rnd, "<", "/dev/urandom"; 
		read $rnd, $r, 32;
	close $rnd;		
	
	my $d = Digest::MD5->new();
	$d->add($r.time().VERSION.$0);
	my $rd = $d->hexdigest;
	
	my $aid_path 	= TMP ."/".$rd."/";
	make_path(TMP, {chmod => 0755});
	make_path($aid_path, {chmod => 0755});
	
	copy($ConfigHash->{"send_logfile"}	,$aid_path) if -e $ConfigHash->{"send_logfile"}; 
	copy($ConfigHash->{"send_model"}	,$aid_path) if -e $ConfigHash->{"send_model"}; 
	copy($ConfigHash->{"send_text"}		,$aid_path) if -e $ConfigHash->{"send_text"}; 
	copy($ConfigHash->{"send_train"}	,$aid_path) if -e $ConfigHash->{"send_train"}; 
	copy($ConfigHash->{"send_library"}	,$aid_path) if -e $ConfigHash->{"send_library"}; 
	copy($ConfigHash->{"send_model_cpu"},$aid_path) if -e $ConfigHash->{"send_model_cpu"}; 
	copy($ConfigHash->{"send_model_gpu"},$aid_path) if -e $ConfigHash->{"send_model_gpu"}; 
		
	#	my $s1 = $ConfigHash->{"send_logfile"};
	#	my $s2 = $ConfigHash->{"send_model"};
	#	my $s3 = $ConfigHash->{"send_text"};
	#	my $s4 = $ConfigHash->{"send_train"};
	#	my $s5 = $ConfigHash->{"send_sample"};
	#	my $s6 = $ConfigHash->{"send_library"};

	#system("tar cvf $tar_file --add-file=$s1 --add-file=$s2 --add-file=$s3 --add-file=$s4 --add-file=$s5 --add-file=$s6 --ignore-failed-read");
	
	my $tar_file 	= TMP."/".$aid."_".time().".tar";
	my $tar_include = $aid_path."*";
	
	#print("tar -C $aid_path . -vv -cf $tar_file $aid_path --ignore-failed-read");
	#system("tar -C $aid_path . -vv -cf $tar_file $aid_path --ignore-failed-read");
	
	# Do not fucking change this :-( -> took me 20 min to find this query
	system("tar -C $aid_path -vv -cf $tar_file --ignore-failed-read .");
	system("bzip2 -9 $tar_file");
	
	my $dataL;
	{
		local $/ = undef;
		open(FILE, "<$tar_file.bz2");
		binmode(FILE);
		$dataL = <FILE>;
		close FILE;
	}
	my $di = Digest::MD5->new();
	$di->add($dataL);
	my $hd = $di->hexdigest;
	
	# Send file to tech.onetipp.net back
	my $file 		= "$tar_file.bz2";
	my $ba			= "OneTIPP (ClientManager.pl)/$v/sendTask()";
	local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
	
	my $ua 			= LWP::UserAgent->new( 
		max_redirect 	=> 10, 
		env_proxy 		=> 0,
		keep_alive 		=> 1, 
		timeout 		=> $seconds, 
		agent 			=> $ba
	);
	
	my $i1 				= $aid."_".time().".tar.bz2";
#	print "aid_filename: $i1\n";
#	print "aid_filehash: $hd\n";
#	print "aid: $aid\n";
#	print "file: $file\n";
#	if (!-e $file){
#		print "$file not existing";
#	}
						  
	my $resp 			= $ua->request(POST $url,
			Content_Type 		=> 'multipart/form-data',
			Content				=> [ 
				upload 			=> [$file],
				aid_filename 	=> $i1,
				aid_filehash 	=> $hd,
				aid_hash		=> $aid,
			]);	
	
	if ($resp->code == 200){
		print "{SUCCESS} sendTask(): Sending: \"$url\": ". $resp->code. "\n";
		return 1;
	} else {
		print "{FAILURE} sendTask(): Sending: \"$url\": ". $resp->code. "\n";
		return 0;
	}
			
} # sub sendTask(){

sub getTask(){
	$ConfigHash		= ();
	%ConfigHash		= {};

	my $starturl	= HOME;
	my $t 			= $starturl ."?action=getTask";
	my $xmlIA 		= &getWebContent($t);
	
	my (@la) 		= ($xmlIA =~ m#\<language\>(.*?)\<\/language\>#igs);
	my (@wo) 		= ($xmlIA =~ m#<worktime>(.*?)<\/worktime>#igs);
	my (@ai) 		= ($xmlIA =~ m#<aid>(.*?)<\/aid>#igs);
	my (@tt) 		= ($xmlIA =~ m#\<traintext\>(.*?)\<\/traintext\>#igs);
	my (@ti) 		= ($xmlIA =~ m#\<timestamp\>(.*?)\<\/timestamp\>#igs);

	my $language	= pop @la;
	my $worktime 	= pop @wo;
	my $aid 		= pop @ai;
	my $text 		= pop @tt;
	my $time 		= pop @ti;
	my $de_text		= decode_entities($text);
	
	my $last_char 	= substr($worktime, -1);
	my $till_last	= substr($worktime, 0, length($worktime)-1);
	my $runtime_sec = ($till_last*$TimeHash->{$last_char});
	#print "Worktime: $till_last with -> $last_char: Runtime in Seconds:$runtime_sec\n";

	my $cv 			= DEEP_CV."/".$aid;
	my $dtd 		= DEEP_DATA."/".$aid;

	make_path($cv,{chmod => 0755});
	make_path($dtd,{chmod => 0755});

	$ConfigHash->{"run_till"}		= time()+$runtime_sec;
	$ConfigHash->{"runtime"}		= $runtime_sec;
	$ConfigHash->{"aid"} 			= $aid;
	$ConfigHash->{"lang"} 			= $language;
	$ConfigHash->{"org_text"} 		= $text;
	$ConfigHash->{"dec_text"} 		= $de_text;
	$ConfigHash->{"cv"} 			= $cv."/";
	$ConfigHash->{"data"} 			= $dtd."/";
	$ConfigHash->{"send_logfile"} 	= HOME_DIR."/"."logfile.txt";
	$ConfigHash->{"send_model_cpu"} = $cv."/"."onetipp.latest.gpu";
	$ConfigHash->{"send_model_gpu"} = $cv."/"."onetipp.latest.cpu";
	$ConfigHash->{"send_text"} 		= $dtd."/"."input.txt";
	$ConfigHash->{"send_train"} 	= TRAIN;
	$ConfigHash->{"send_sample"} 	= SAMPLE;
	$ConfigHash->{"send_library"} 	= LIBRARY;

	open my $OUT, '>:encoding(UTF-8)', $dtd."/"."input.txt";
		print $OUT $de_text;
	close($OUT);
#	open(OUT1, ">".$dtd."/"."input.txt");
#		binmode(OUT1);
#		print OUT1 $de_text;
#	close(OUT1);

	return $ConfigHash;
} # sub getTask(){

sub ForceClientManagerUpdate(){
	my $hash 	= shift;
	#print Dumper $hash;
	my $script 	= SCRIPT;
	
	while (my ($key, $value) = each %{$hash}){
		while (my ($key2, $value2) = each %{$value}){
			if ($key2=~/md5/ig){
				my $md5xml 		= $hash->{$key}->{'md5'};
				my $durl 		= $hash->{$key}->{'url'};
				my $dpath 		= $hash->{$key}->{'path'};
				next if ($durl !~ /(ftp|ftps|http|https)/ig || $md5xml !~ /[a-z0-9]/ig);
				make_path($dpath, {chmod => 0755,});
				
				my $dcontent 	= &getWebContent($durl);
				my $filename 	= basename($durl);
				my $file 		= "$dpath/$filename";
				my $w_path 		= substr $dpath, -1;
				if ($w_path eq "/"){
					$file 		= $dpath.$filename;
				}
				
				# save compressed file
				open (OUT1, ">$file");
					binmode(OUT1);
					print OUT1 $dcontent;
				close OUT1;
			
				my $trf = "/tmp/".rand();
				copy($script,$trf) or warn "Could not copy";
				system("bzip2 -9 $trf");
				my $ccfile = $trf.".bz2";
				
				my $dataL;
				{
					local $/ = undef;
					open(FILE, "<$ccfile");
					binmode(FILE);
					$dataL = <FILE>;
					close FILE;
				}
				unlink $ccfile;
				unlink $trf;
				
				my $dig = Digest::MD5->new();
				$dig->add($dataL);
				print "$ccfile: ".$dig->hexdigest."\n";
				
				if ($dig->hexdigest eq $md5xml){
					# md5 value of given and downloaded file is same 
					# this means that our current running version and the remote version are same
					print "ForceClientManagerUpdate(): I am running the latest version\n";
					
				} else {
					print "ForceClientManagerUpdate(): MD5 Value of Remote ClientManager and our Local ClientManager differs -> will start the downloaded new version -> Good Bye\n";
					
					# copy file to random path
					# uncompress
					# start: $file
					
					my $r;
					my $rnd;
					open $rnd, "<", "/dev/urandom"; 
					read $rnd, $r, 32;
					
					my $d = Digest::MD5->new();
					$d->add($r.time().VERSION.$0);
					my $rd = $d->hexdigest;
					
					my $rdfile_bz2 	= "$dpath/$rd.pl.bz2";
					my $rdfile 		= "$dpath/$rd.pl";
					
					if ($w_path eq "/"){
						$rdfile_bz2 = $dpath."$rd.pl.bz2";
						$rdfile 	= $dpath."$rd.pl";
					}
				
					#print "dpath:$dpath\n";
					#print "rdfile:$rdfile\n";
					#print "rdfile_bz2:$rdfile_bz2\n";
					
					copy($file,$rdfile_bz2) or warn "Could not copy";
					system("bunzip2 $rdfile_bz2"); 
				
					my $size = -s $rdfile;
					if ($size >= 1024 && -e $rdfile){
						
						print "I am restarting with latest, downloaded version: \"$rdfile\"\n";
						
						# comment out for live version
						#exec("perl $rdfile");
						
					} # if ($size >= 1024 && -e $rdfile){
				} # if ($dig->hexdigest eq $md5xml){
			} # if ($key2=~/md5/ig){
		} # while (my ($key2, $value2) = each %{$value}){
	} # while (my ($key, $value) = each %{$hash}){
	return 1;
} # sub ForceClientManagerUpdate(){

sub DeepLearningTrainingSoftwareUpdate(){
	my $hash 	= shift;
	
	while (my ($key, $value) = each %{$hash}){
		#print "k1:$key und v1:$value\n";
		while (my ($key2, $value2) = each %{$value}){
		#	print "k2:$key2 und v2:$value2\n";
			if ($key2=~/path/ig){
				my $durl 		= $hash->{$key}->{'url'};
				my $dpath 		= $hash->{$key}->{'path'};
				my $w_path 		= substr $dpath, -1;
				
				print "DeepLearningTrainingSoftwareUpdate(): MKDIR \"$dpath\"\n";
				make_path($dpath, {chmod => 0755,});
				next if ($durl !~ /(ftp|ftps|http|https)/ig);
				
				my $dcontent 	= &getWebContent($durl);
				my $filename 	= basename($durl);

				my $file 		= "$dpath/$filename";
				if ($w_path eq "/"){
					$file 		= $dpath.$filename;
				}
				
				# download compressed file
				open (OUT1, ">$file");
					binmode(OUT1);
					print OUT1 $dcontent;
				close OUT1;
			
				$ConfigHash->{"deep".$key} = $file;
		
				# keep this file, later do MD5 check against it, when updating
				open (OUT2, ">$file.otp");
					binmode(OUT2);
					print OUT2 $dcontent;
				close OUT2;
				
				# uncompress
				system("bunzip2 $file"); 
			} # if ($key2=~/path/ig){	
		} # while (my ($key, $value) = each %{$hash}){
	} # while (my ($key, $value) = each %{$hash}){
	return 1;
} # sub DeepLearningTrainingSoftwareUpdate(){

sub ForceInternalDockerImageAPTUpdate(){
	my $hash 	= shift;
	my $seconds = UPDATETIME;
	my $opts  	= {'die_upon_destroy' => 1};
	
	while (my ($key, $value) = each %{$hash}){
		my $command = $value->{'exec'};
		print "ForceInternalDockerImageAPTUpdate(): Executing \"$command\"\n";
		# timeout_system($seconds, $command,);
		my $proc1 	= Proc::Background->new($opts, $command,,);
		my $ptime 	= time();
		my $kpid 	= $proc1->pid;
		while ($proc1->alive){
			my $ctime = time();
			if ($ctime>=($ptime+$seconds)){
				print "ForceInternalDockerImageAPTUpdate(): Terminating Program: \"$command\" after $seconds sec of Runtime with PID $kpid\n";
				$proc1->die;
				system("kill -9 $kpid");
			} else {
				print "ForceInternalDockerImageAPTUpdate(): Wait To finish Program: \"$command\" with PID $kpid\n";
				$proc1->wait;
			}
			sleep 10;
		} # while ($proc1->alive){
	} # while (my ($key, $value) = each %{$hash}){
} # sub ForceInternalDockerImageAPTUpdate(){

sub parseStartXML(){
	# return ($ForceClientManagerUpdate, $ForceInternalDockerImageAPTUpdate, $ForceDeepLearningTrainingSoftwareUpdate);
	
	my $StartXML 	= shift;
	my $ref 		= XMLin($StartXML);

	my $ForceDeepLearningTrainingSoftwareUpdate = ();
	my %ForceDeepLearningTrainingSoftwareUpdate = {}; 
	my $ForceInternalDockerImageAPTUpdate = ();
	my %ForceInternalDockerImageAPTUpdate = {}; 
	my $ForceClientManagerUpdate = ();
	my %ForceClientManagerUpdate = {};
	my $y = 0;

	while (my ($key, $value) = each %{$ref->{'ForceDeepLearningTrainingSoftwareUpdate'}}){
		#print "k: $key und v: $value\n";
		if ($key =~ /(\d)$/){
		#	print "match: $1\n";
			$y = $1;	# from <md5filehash2> get -> "2"
		}; 	
		if ($key=~/md5filehash/ig){
			$ForceDeepLearningTrainingSoftwareUpdate->{$y}->{"md5"} = $value;
		} elsif ($key=~/fetchurl/ig){
			$ForceDeepLearningTrainingSoftwareUpdate->{$y}->{"url"} = $value;
		} elsif ($key=~/storepath/ig){
			$ForceDeepLearningTrainingSoftwareUpdate->{$y}->{"path"} = $value;
		}
	} # while (my ($key, $value) = each %{$ref->{'ForceClientManagerUpdate'}}){

	my $y = 0;
	while (my ($key, $value) = each %{$ref->{'ForceInternalDockerImageAPTUpdate'}}){
		#print "k: $key und v: $value\n";
		if ($key =~ /(\d)$/){
			#print "match: $1\n";
			$y = $1;	# from <md5filehash2> get -> "2"
		}; 	
		if ($key=~/exec_command/ig){
			$ForceInternalDockerImageAPTUpdate->{$y}->{"exec"} = $value;
		}
	} # while (my ($key, $value) = each %{$ref->{'ForceClientManagerUpdate'}}){

	my $y = 0;
	while (my ($key, $value) = each %{$ref->{'ForceClientManagerUpdate'}}){
		#print "k: $key und v: $value\n";
		if ($key =~ /(\d)$/){
			#print "match: $1\n";
			$y = $1;	# from <md5filehash2> get -> "2"
		}; 	
		if ($key=~/md5filehash/ig){
			$ForceClientManagerUpdate->{$y}->{"md5"} = $value;
		} elsif ($key=~/fetchurl/ig){
			$ForceClientManagerUpdate->{$y}->{"url"} = $value;
		} elsif ($key=~/storepath/ig){
			$ForceClientManagerUpdate->{$y}->{"path"} = $value;
		}
	} # while (my ($key, $value) = each %{$ref->{'ForceClientManagerUpdate'}}){

	return ($ForceClientManagerUpdate, $ForceInternalDockerImageAPTUpdate, $ForceDeepLearningTrainingSoftwareUpdate);
} # sub parseStartXML(){

sub getWebContent(){

	my $url 		= shift;
	my $v 			= VERSION;
	my $seconds 	= UPDATETIME;
	my $ba			= "OneTIPP (ClientManager.pl)/$v/getWebContent()";
	
	my $ua 			= LWP::UserAgent->new( 
		max_redirect => 10, 
		env_proxy => 0,
		keep_alive => 1, 
		timeout => $seconds, 
		agent => $ba
	);
		
	my $response 	= $ua->get($url);
	
	print "getWebContent(): Downloading: \"$url\" with UserAgent \"$ba\"\n";
	if ($response->code == 200){
		print "{SUCCESS} getWebContent(): Downloading: \"$url\"\n";
		#my $content = $response->decoded_content();
		return $response->content();
	} else {
		print "{FAILURE} getWebContent(): Downloading: \"$url\"\n";
		return 0;
	}
	print "{FAILURE} getWebContent(): Downloading: \"$url\"\n";
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

sub init(){
	my $h 	= HOME_DIR;
	my $cv 	= DEEP_CV;
	my $dd 	= DEEP_DATA;
	
	make_path($h, {chmod => 0755});
	make_path($cv,{chmod => 0755});
	make_path($dd,{chmod => 0755});
	
	return 1;
} # sub init(){

sub signal_handler(){
    print "Caught signal $_[0]!\n";
	print Dumper $hash;
	&sendTask($hash);
	exit(0);
} # sub signal_handler(){