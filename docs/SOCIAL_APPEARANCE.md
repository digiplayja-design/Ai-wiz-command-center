# Social themes and skins

Social has a palette shortcut in its header and a **Themes & skins** item in its settings and private-conversation menus. The picker reuses Korlix's 12 color palettes, 10 static skins and 18 curated looks, with a Social conversation preview in the hero and gallery. Previewing or closing the picker does not change the applied appearance. **Apply look** saves it; **Use app appearance** restores inheritance from the app.

The selection lives in the device's `korlix_social_appearance_v1` preference. It changes only this device's Social UI, not the app-wide preference, a member's profile color, other members' screens, or a server record. A failed device write is reported and keeps the choice for the current session. Restore and queued writes are revision-guarded so a late load cannot replace a newer choice.

`SocialPageRoute` puts the live theme above each Social route, including entry from message/online alerts and restored calls. The inherited appearance also travels into dialogs. `SocialScaffold` paints the static skin behind the page, and Social panels and message bubbles use matching surfaces and corners. Explicit media/game backgrounds remain controlled by their viewers. No decorative element handles input or adds continuous animation or blur.

Changing the look retains page elements and controllers. Verification covers persistence and app isolation, delayed restore, storage failure, preview/cancel/apply/follow-app behavior, route inheritance, real chat draft and scroll preservation, and narrow-phone/large-text/tablet layouts. The Social appearance checks are part of the web release gate.
