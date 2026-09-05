# K135Z Nova Meeting Copilot UI foundation

This isolated Flutter foundation provides:

- required injection points for the exact official KORLIX logo and the approved canonical Nova portrait;
- explicit Zoom-connected, host-authorized, listening, paused, speaking, stopped, and error states;
- Nova muted by default and a hard host-invite gate before `Speak Now` can activate;
- live transcript preview with participant and timestamp attribution;
- separate panels for decisions, action items, deadlines, risks, open questions, and key takeaways;
- controls for Connect Zoom, Start Listening, Pause Listening, Stop Listening, Ask Nova, 30-Second Update, Speak Now, and Mute Nova;
- accessible text labels that do not rely on glow or color alone.

This stage is not mounted in `lib/main.dart`, does not change `pubspec.yaml`, does not select an unverified image asset, and makes no network, Zoom, Render, Supabase, email, recording, or audio-output call. The next integration stage must bind the two required `ImageProvider` values to the verified canonical repository assets before route activation.


## B3 canonical asset and route integration

The `/meeting-copilot` named route binds the exact official KORLIX corporate
mark separately from Nova's canonical assistant portrait. The route owns a
`NovaMeetingCopilotController`, preserves Nova's muted-by-default behavior,
and disposes the controller when the route closes where supported.
