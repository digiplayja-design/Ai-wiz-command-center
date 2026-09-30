# Social message notifications on the KORLIX home screen

The home screen shows a notification card below its header when the signed-in
account has unread private or group messages. The Social tool also shows the
unread count. Tapping a single conversation opens it directly; multiple
conversations open a selector. The chat's existing read behavior clears counts
after messages are viewed. Opening the notification selector does not mark read.

The controller reads the authenticated `connections` and `groups` APIs every five
seconds while the home route is visible and the app is foregrounded. It follows
40-row pagination, deduplicates conversations, and uses server unread counts.
No message notification writes or new database permissions are needed.

Sign-out, session replacement, and denied access clear notification data. Old
responses cannot populate a new account. Temporary network failures retain the
last confirmed counts and retry on a later poll. Closing Social refreshes the
home counts immediately. No notification content is stored on the device.

This is an in-app home-screen notification. It does not register device push
tokens, show lock-screen notifications, or send alerts while the app is closed.
Web publication takes effect after refreshing the app; installed mobile apps
need a new store build containing these Flutter source changes.

Focused checks: `flutter test test/social_notifications_test.dart`. Exercise
pagination, private/group counts, hidden-app polling, request coalescing,
temporary failures, revoked access, account changes, banner navigation, and read
count refresh. Also verify the existing Social chat tests and a release build.

Live acceptance: with two consenting test accounts already connected in Social,
leave the recipient on the KORLIX home screen and send a private message. Expect
the alert within about five seconds. Tap it, read the message, and return home;
the count should clear. Repeat in an accepted group conversation.
