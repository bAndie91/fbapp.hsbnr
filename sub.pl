
use Data::Dumper;
use LWP::UserAgent;
use Carp;
use Digest::SHA qw/hmac_sha256_hex/;


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
	# Arguments
	#  - [0]: an ARRAY or a HASH ref
	#    - case ARRAY:
	#      - [0]: recipient id
	#      - [1]: message text
	#    - case HASH: the whole message object
	#  - [1]: a HASH ref of options
	#    - parts (boolean) : whether send any length message by splitting it into chunks
	# Returns boolean
	#  - TRUE on success
	#  - FALSE on fail, sets $ERRORMESSAGE global
	
	my $msgobj = {};
	if(ref $_[0] eq 'ARRAY')
	{
		$msgobj->{'recipient'}->{'id'} = $_[0][0];
		$msgobj->{'message'}->{'text'} = $_[0][1];
	}
	elsif(ref $_[0] eq 'HASH')
	{
		$msgobj = $_[0];
	}
	else
	{
		croak "invalid argument type";
	}
	my %opt = %{$_[1]};
	
	if(not defined $send_message_user_agent)
	{
		$send_message_user_agent = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0, });
	}
	
	$msgobj->{'messaging_type'} = 'MESSAGE_TAG';
	$msgobj->{'tag'} = 'COMMUNITY_ALERT';
	
	my $url = "$ini{'api'}{'BaseURL'}/me/messages?access_token=$ini{'api'}{'PageAccessToken'}&appsecret_proof=$appsecret_proof";
	my $resp;
	for my $chunk ($opt{'parts'} ? (partitions($msgobj->{'message'}->{'text'}, $ini{'api'}{'charlimit'})) : $msgobj->{'message'}->{'text'})
	{
		$msgobj->{'message'}->{'text'} = $chunk;
		$resp = $send_message_user_agent->post($url, 'Content-Type'=>'application/json', Content=>to_json($msgobj));
		if(not $resp->is_success)
		{
			#print STDERR Dumper $resp->decoded_content;
			last;
		}
	}
	
	if(not $resp->is_success)
	{
		print STDERR join "\n", grep {!/^((Cache-Control|Connection|Content-Length|Date|Pragma|Vary|WWW-Authenticate|Content-Type|Expires|Access-Control-Allow-Origin):|Client-SSL|$)/} split /\r?\n/, $resp->as_string;
		eval {
			$ERRORMESSAGE = from_json($resp->content)->{'error'}->{'message'};
			1;
		};
		return 0;
	}
	return 1;
}

sub array
{
	# Typecast non-array variable to array.
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

sub partitions
{
	my $remaining_str = shift;
	my $max_len = shift;
	my $boundary_char = shift;
	$boundary_char = "\n" unless defined $boundary_char;
	my @parts;
	# TODO partition prefix and suffixes
	while(length $remaining_str)
	{
		my $chunk = substr $remaining_str, 0, $max_len;
		if(length $boundary_char)
		{
			$pos = rindex $remaining_str, $boundary_char;
			if($pos > 0)
			{
				$chunk = substr $remaining_str, 0, $pos;
			}
		}
		if(length $boundary_char and $chunk eq $boundary_char) { 1; }
		else { push @parts, $chunk; }
		$remaining_str = substr $remaining_str, length $chunk;
	}
	return @parts;
}

sub datetime_iso8601
{
	return POSIX::strftime('%FT%TZ%z', localtime);
}

sub hash_of_delimited_strings_to_nested_hash
{
	sub dive_val :lvalue {
		my $p = \shift;
		$p = \( ($$p)->{$_} ) for @_;
		return $p;
	}
	my $hashref = {};
	for my $key (keys $_[0])
	{
		${dive_val($hashref, split /\./, $key)} = $_[0]->{$key};
	}
	return $hashref;
}

sub appsecret_proof
{
	return hmac_sha256_hex($ini{'api'}{'PageAccessToken'}, $ini{'api'}{'AppSecretKey'});
}

1;
