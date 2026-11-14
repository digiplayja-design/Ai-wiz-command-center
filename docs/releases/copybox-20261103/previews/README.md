# COPY Box interface previews

These images were rendered from the actual Flutter interface with sample text.
They show the app content, without simulated phone hardware or operating-system
status bars. They are interface previews, not proof of physical-device testing.

| Image | Layout |
| --- | --- |
| `copybox-workspace.png` | Phone workspace, 390 × 844 logical pixels |
| `copybox-templates.png` | Phone templates, 390 × 844 logical pixels |
| `copybox-desktop-dark.png` | Large-screen dark appearance, 1280 × 900 logical pixels |

The images use three output pixels per logical pixel and the SDK's Roboto and
Material icon fonts. The text is a fixture; no customer workspace or credentials
are shown.

Source: `85e2c9e52cc3564c26cfe1720a4c2b0b9121df5d`,
[CI run 41738481269](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41738481269),
artifact `13280916031`. The application source, native configuration, assets, and
locked dependencies are unchanged in validation commit
`de58d87d0277759db87d20abc048358e6ab4f89c`; that commit changes test cleanup and
compiled-APK inspection only.

The KORLIX emblem is the app's white-on-black branding asset. These screenshots
were not synthesized by an image-generation model.
