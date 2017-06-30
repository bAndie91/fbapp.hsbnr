Email headers considered
====

 - `Subject`
 Enumerate semicolor-delimited topic names in Subject header.
 
 - `X-Uucphu-Notify-App-Want-Trim: 1`
 Notify App will trim the message at the max length accepted by Messenger.

Topic name syntax
====

Topic name can be any string with the following semantics.
Topics are hierarchical sequence of dot-delimited labels (like DNS, but in reverse direction).
Separate multiple topics with semicolon.
Separate multiple labels with comma to refer to multiple topics with one or more common labels.

Examples for publishing notifications
----

 - `system.alert.service.httpd`
 - `system.alert.service.httpd,smtpd,imapd` expands to
   - `system.alert.service.httpd`
   - `system.alert.service.smtpd`
   - `system.alert.service.imapd`
 - `system.alert.service.httpd;user.apache` expands to
   - `system.alert.service.httpd`
   - `user.apache`

Examples to subscribe notifications
----

 - `system.alert`
   - matches to
     - `system.alert`
     - `system.alert.anything`
     - `system.alert.anything.anydepth`
   - does not match to
     - `system.alerting`
     - `subsystem.alert`
 - `user.*.login`
   - matches to
     - `user.root.login.tty0`
   - does not match to
     - `user.root.label.login`
 - `user.**.login`
   - matches to
     - `user.root.label.login`
 - `*`
   - matches to everything
