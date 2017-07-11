#!/usr/bin/env perl
#
# http://m.me/uucp.hu
#

use Data::Dumper;
use feature qw/switch/;
use Cwd;
use Config::IniFiles;
use JSON;
use POSIX;
require "/usr/share/libcgi-yazzy/cgi.pl";
require "/opt/fbapp/notify/sub.pl";

tie %ini, 'Config::IniFiles', (-file => "/opt/fbapp/notify/conf/app.ini", -nocase => 1, -nomultiline => 1);


#print STDERR Dumper {'POST'=>\%_POST, 'GET'=>\%_GET,};


print "Status: 200", $CRLF;
print "Content-Type: application/json", $CRLF;
print $CRLF;

if($_GET{'hub.mode'} eq 'subscribe')
{
	if($_GET{'hub.verify_token'} eq $ini{'api'}{'VerifyToken'})
	{
		print $_GET{'hub.challenge'};
	}
	exit 0;
}

($RAWPOST) = (keys %_POST);
eval {
	$apiobj = from_json($RAWPOST);
	1;
}
or die $@.'POST: '.Dumper(\%_POST);

#print STDERR Dumper $apiobj;
$subscribers_changed = 0;
@responses = ();


for my $entry (@{$apiobj->{'entry'}})
{
	for my $messaging (@{$entry->{'messaging'}})
	{
		my $sender_id = $messaging->{'sender'}->{'id'};
		if($sender_id !~ /^\d+$/)
		{
			# Not a Facebook Id
			next;
		}
		my $message_text = $messaging->{'message'}->{'text'};
		my $postback_payload = $messaging->{'postback'}->{'payload'};
		my $quick_reply_payload = $messaging->{'message'}->{'quick_reply'}->{'payload'};
		my $command = $postback_payload || $quick_reply_payload || $message_text;
		my $subs_changed = 0;
		
		given($command)
		{
			when(/^LIST SUBS/i)
			{
				my $list = join "\n", map {"☑ $_"} get_subscriptions($sender_id);
				push @responses, [$sender_id, $list ? "You are subscribed for:\n$list" : "No subscription yet."];
			}
			when(/^LIST TOPICS/i)
			{
				my $list = join "\n", map {"☐ $_"} sort keys $ini{'topic'};
				push @responses, [$sender_id, $list ? "Known topics:\n$list" : "There is no known topic."];
			}
			when(/^UNSUB ALL/i)
			{
				delete $ini{'subscribe'}{$sender_id};
				$ini{'unsubscribe'}{$sender_id} = datetime_iso8601();
				$subs_changed = 1;
				$subscribers_changed = 1;
				push @responses, [$sender_id, "You are unsubscribed from all topics."];
			}
			when(/^HELP/i)
			{
				my @quick_replies;
				for my $ref (["LIST SUBS", "My Subscriptions"], ["LIST TOPICS", "Known Topics"], ["UNSUB ALL", "Unsubscribe all"])
				{
					my $payload = $ref->[0];
					my $title = $ref->[1];
					push @quick_replies, {'title'=>$title, 'content_type'=>'text', 'payload'=>$payload, 'image_url'=>$ini{'quickbutton-icon-url'}{$payload},};
				}
				push @responses, {
					'recipient'=>{'id'=>$sender_id},
					'message'=>{
						'text' => "Click button below or type \"SUBS topic1; topic2; ...\"",
						'quick_replies' => \@quick_replies,
					},
				};
			}
			when(/^\s*(un)?sub\S*\s+(.+)/i)
			{
				my $unsub = (defined $1 ? 1 : 0);
				my @topics = expand_topics($2);
				
				if(@topics)
				{
					my @subs = get_subscriptions($sender_id);
					if($unsub)
					{
						my $new_topic_patterns = [];
						for my $topic_pattern (@subs)
						{
							if(not grep {$topic_pattern eq $_} @topics)
							{
								push @$new_topic_patterns, $topic_pattern;
							}
						}
						if(scalar @subs != scalar @$new_topic_patterns)
						{
							$ini{'subscribe'}{$sender_id} = $new_topic_patterns;
							$subs_changed = 1;
							$subscribers_changed = 1;
						}
					}
					else
					{
						delete $ini{'unsubscribe'}{$sender_id};
						my %new_topic_patterns = map {$_=>1} @topics, @subs;
						delete $ini{'subscribe'}{$sender_id};
						@{$ini{'subscribe'}{$sender_id}} = keys %new_topic_patterns;
						$subs_changed = 1;
						$subscribers_changed = 1;
					}
				}
				else
				{
					push @responses, [$sender_id, $unsub ? "What do you want to unsubscribe from?" : "What do you want to subscribe for?"];
				}
			}
		}
		
		if(not exists $ini{'user-joined'}{$sender_id})
		{
			$ini{'user-joined'}{$sender_id} = datetime_iso8601();
			my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0, });
			my $resp = $ua->get("$ini{'api'}{'BaseURL'}/$sender_id?access_token=$ini{'api'}{'PageAccessToken'}");
			eval {
				my $user = from_json($resp->decoded_content);
				$ini{'user-name'}{$sender_id} = sprintf '%s %s %s', $user->{'first_name'}, $user->{'middle_name'}, $user->{'last_name'};
				$ini{'user-locale'}{$sender_id} = $user->{'locale'};
				1;
			} or print STDERR $@;
			$subscribers_changed = 1;
		}
		
		if($subs_changed)
		{
			push @responses, {
				'recipient'=>{'id'=>$sender_id},
				'message'=>{
					'text' => "Your subscriptions are changed.",
					'quick_replies' => [{
						'title' => "My Subscriptions",
						'content_type' => 'text',
						'payload' => "LIST SUBS",
						'image_url' => $ini{'quickbutton-icon-url'}{"LIST SUBS"},
					}],
				},
			};
		}
	}
}


if($subscribers_changed)
{
	update_ini();
}

for my $response (@responses)
{
	send_message($response, {'parts'=>1});
}
