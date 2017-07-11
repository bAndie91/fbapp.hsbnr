#!/usr/bin/env perl

use Cwd;
use Config::IniFiles;
use JSON;
use LWP::UserAgent;
require "/opt/fbapp/notify/sub.pl";

tie %ini, 'Config::IniFiles', (-file => "/opt/fbapp/notify/conf/app.ini", -nocase => 1, -nomultiline => 1);


$ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0, });
$url = "$ini{'api'}{'BaseURL'}/me/messenger_profile?access_token=$ini{'api'}{'PageAccessToken'}";

$resp = $ua->post($url, 'Content-Type'=>'application/json', Content=>to_json(
{
  "persistent_menu"=>[
    {
      "locale"=>"default",
      "composer_input_disabled"=>0,
      "call_to_actions"=>[
        {
          "title"=>"List",
          "type"=>"nested",
          "call_to_actions"=>[
            {
              "title"=>"My Subscriptions",
              "type"=>"postback",
              "payload"=>"LIST SUBS"
            },
            {
              "title"=>"Known Topics",
              "type"=>"postback",
              "payload"=>"LIST TOPICS"
            },
          ],
        },
        {
          "title"=>"Unsubscribe All",
          "type"=>"postback",
          "payload"=>"UNSUB ALL"
        },
        {
          "title"=>"Commands Help",
          "type"=>"postback",
          "payload"=>"HELP"
        },
      ],
    },
  ],
}));

print STDERR $resp->as_string;
