# KORLIX Logo Studio

Open from the home screen's For business section or More tools. Users enter a brand brief, choose one of six locally composed directions, edit the mark/layout/colors/type treatment, and export. Local generation does not call an AI service or consume a generation credit.

The optional AI exploration action uses the existing authenticated ImagineClient and `/api/image/create`, with the existing consent, quota, and billing checks. AI artwork remains PNG and is clearly separate from editable vector designs. This feature does not vectorize AI artwork, promise uniqueness, or perform trademark clearance.

SVG and Canvas share geometry and lettering calculations. SVG embeds the matching Roboto fonts and retains editable text. PNG exports contain real alpha transparency. Brand kits contain color/black/white SVG, 2400x1600 PNG variants, social assets, a PDF guide, licensed fonts, and a versioned JSON project. Some SVG editors require installation of the bundled fonts.

Projects are explicitly saved to account-scoped local preferences, up to 20. They do not sync across devices; JSON import/export provides portability. Import accepts only bounded structured project data, not SVG or executable markup. Account changes clear visible designs and ignore pending loads or exports. No database or backend changes are required.

Validation: `flutter test test/logo_studio_test.dart test/imagine_studio_test.dart test/korlix_action_button_test.dart`. Screenshot and export fixtures use `AGENT_STUDIO_SCREENSHOTS`; generation/share/file-picker tests use test doubles and do not contact users or run paid production generations.
