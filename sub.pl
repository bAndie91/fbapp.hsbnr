
use Data::Dumper;
use LWP::UserAgent;


sub expand_topics
{
	my @topics;
	for my $topic_pack (split /\s*;\s*/, $_[0])
	{
		push @topics, expand_topic_labels($topic_pack);
	}
	return @topics;
}

sub expand_topic_labels
{
	my @topics;
	for my $label (split /\./, $_[0])
	{
		my @labels = map {s/^\s*//; s/\s*$//; $_} split /,/, $label;
		if(not @topics)
		{
			for my $root_label (@labels)
			{
				push @topics, $root_label;
			}
		}
		else
		{
			my $shift = 0;
			for my $n (0..$#topics)
			{
				my $idx = $n + $shift;
				my $topic_base = $topics[$idx].'.';
				my $a = 0;
				for my $append_label (@labels)
				{
					my $idx = $n + $shift;
					if($a == 0)
					{
						$topics[$idx] = $topic_base.$append_label;
					}
					else
					{
						splice @topics, $idx+1, 0, $topic_base.$append_label;
						$shift++;
					}
					$a++;
				}
			}
		}
	}
	return @topics;
}

sub topic_match
{
	my $name = shift;
	my $pattern = shift;
	my $regex = $pattern;
	$regex =~ s/(\*\*|\*|[^\*]+)/topic_pattern_substr_to_regex($1)/eg;
	$regex = '^'.$regex.'(?:\.|$)';
	return $name =~ $regex;
}

sub topic_pattern_substr_to_regex
{
	my $s = shift;
	if($s eq '**')	{ return '.+'; }
	if($s eq '*')	{ return '[^\.]+'; }
	if($s eq '.')	{ return '\.'; }
	return quotemeta $s;
}

sub update_ini
{
	my $inipath = tied(%ini)->GetFileName();
	my $tmppath = $inipath.'-tmp';
	umask 007;
	open my $fh, '>>', $ini{'system'}{'lockfile'} or warn$!;
	flock $fh, 2 or warn$!;
	tied(%ini)->WriteConfig($tmppath) or warn "WriteConfig error";
	rename $tmppath, $inipath or warn$!;
	close $fh or warn$!;
}

sub send_message
{
	# Arguments variant 1
	#  - recipient id
	#  - message text
	# Arguments variant 2
	#  - message object hash
	# Returns boolean
	#  - TRUE on success
	#  - FALSE on fail, sets $ERRORMESSAGE global
	
	my $msgobj = {};
	if(ref $_[0] eq 'ARRAY')
	{
		$msgobj->{'recipient'}->{'id'} = $_[0][0];
		$msgobj->{'message'}->{'text'} = $_[0][1];
	}
	elsif(ref $_[0] eq '')
	{
		$msgobj->{'recipient'}->{'id'} = $_[0];
		$msgobj->{'message'}->{'text'} = $_[1];
	}
	else
	{
		$msgobj = $_[0];
	}
	
	if(not defined $send_message_user_agent)
	{
		$send_message_user_agent = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0, });
	}
	
	my $url = "$ini{'api'}{'BaseURL'}/messages?access_token=$ini{'api'}{'PageAccessToken'}";
	my $resp = $send_message_user_agent->post($url, 'Content-Type'=>'application/json', Content=>to_json($msgobj));
	#print STDERR Dumper $resp->decoded_content;
	
	if(not $resp->is_success)
	{
		print STDERR join "\n", grep {!/^((Cache-Control|Connection|Content-Length|Date|Pragma|Vary|WWW-Authenticate|Content-Type|Expires|Access-Control-Allow-Origin):|Client-SSL|$)/} split /\r?\n/, $resp->as_string;
		$ERRORMESSAGE = from_json($resp->content)->{'error'}->{'message'};
		return 0;
	}
	return 1;
}

sub array
{
	# Typecase non-array variable to array.
	my $var = $_[0];
	if(ref $var ne 'ARRAY') { $var = [$var]; }
	return @$var;
}

sub get_subscriptions
{
	my $uid = shift;
	my @list = array($ini{'subscribe'}{$uid});
	return sort grep {length} @list;
}

1;
