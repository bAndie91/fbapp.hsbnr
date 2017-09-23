#!/usr/bin/env perl

use Data::Dumper;
use Switch;
use Cwd;
use Config::IniFiles;
use JSON;
use POSIX;
use Net::Server::Mail::SMTP;
use Email::MIME;
use IO::Socket::INET;
require "/opt/fbapp/hsbnr/sub.pl";

tie %ini, 'Config::IniFiles', (-file => "/opt/fbapp/hsbnr/conf/app.ini", -nocase => 1, -nomultiline => 1);

$smtp = Net::Server::Mail::SMTP->new();
$smtp->set_callback('RCPT' => \&cb_rcpt);
$smtp->set_callback('DATA' => \&cb_data);
$smtp->process();


sub cb_rcpt
{
	my $session = shift;
	my $recipient = shift;
	# return 0, 554, "relay access denied";
	return 1;
}

sub cb_data
{
	my $session = shift;
	my $data = shift;
	my $sender = $session->get_sender();
	my @recipients = $session->get_recipients();
	my @topics;
	my $message_text;
	my $mail = Email::MIME->new($$data);
	my $notifications = {};
	my @smtp_responses;
	my $want_parts = 0;
	my $all_count;
	my $done_count;
	my $inline_metric;
	
	@topics = expand_topics($mail->header('X-HSBNR-Topic')) || expand_topics($mail->header('Subject'));
	if(not @topics)
	{
		return 0, 554, "no valid topic was found";
	}
	
	my $inichanged = 0;
	for(@topics)
	{
		if(not exists $ini{'topic'}{$_})
		{
			$ini{'topic'}{$_} = 1;
			$inichanged = 1;
		}
	}
	if($inichanged)
	{
		update_ini();
	}
	
	# Search message body
	$mail->walk_parts(sub{
		return if $message_text;
		my ($part) = @_;
		return if $part->subparts;
		if($part->content_type =~ m[^text/plain\b]i)
		{
			$message_text = $part->body;
			$message_text =~ s/^\s*//;
			$message_text =~ s/\s*$//;
		}
	});
	
	if(not $message_text)
	{
		return 0, 554, "no valid message text found";
	}
	
	if($message_text =~ s{<metric>(.*?)(</metric>)}{})
	{
		$inline_metric = $1;
		$message_text =~ s/^\s*//;
		$message_text =~ s/\s*$//;
	}
	
	# Push Carbon metric
	if($ini{'system'}{'carbon-node'})
	{
		my $metric_prefix = '';
		if($ini{'system'}{'carbon-prefix'})
		{
			$metric_prefix = $ini{'system'}{'carbon-prefix'}.'.';
		}
		my $carbon_socket = IO::Socket::INET->new($ini{'system'}{'carbon-node'});
		if($carbon_socket)
		{
			my @metrics = expand_topics($inline_metric || $mail->header('X-HSBNR-Metric'));
			@metrics = @topics unless @metrics;
			for my $metric (@metrics)
			{
				$metric =~ s/\s+/_/g;
				printf {$carbon_socket} "%s%s %d %d\n", $metric_prefix, $metric, 1, time;
			}
			close $carbon_socket;
		}
	}
	
	for my $uid (keys $ini{'subscribe'})
	{
		my @user_matched_topics;
		for my $topic_pattern (array($ini{'subscribe'}{$uid}))
		{
			push @user_matched_topics, grep {topic_match($_, $topic_pattern)} @topics;
		}
		if(@user_matched_topics)
		{
			$notifications->{$uid} = \@user_matched_topics;
		}
	}
	
	$all_count = scalar keys $notifications;
	for my $uid (keys $notifications)
	{
		my $mtext = sprintf "%s\n[%s]", $message_text, join ';', @{$notifications->{$uid}};
		if($mail->header('X-HSBNR-Want-Trim') or grep {/trim/i} @recipients)
		{
			$mtext = substr $mtext, 0, $ini{'api'}{'charlimit'};
		}
		elsif($mail->header('X-HSBNR-Want-Partitions') or grep {/part/i} @recipients)
		{
			$want_parts = 1;
		}
		
		if(send_message([$uid, $mtext], {'parts'=>$want_parts}))
		{
			$done_count++;
		}
		else
		{
			push @smtp_responses, $ERRORMESSAGE;
		}
	}
	
	if($all_count and !$done_count)
	{
		return 0, 554, join "\r\n", @smtp_responses;
	}
	else
	{
		return 1, 250, join "\r\n", @smtp_responses, sprintf "%d/%d notifications sent", $done_count, $all_count;
	}
}
