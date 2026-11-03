# In-app purchase review images

This debug-only target renders the unchanged production `BrainBillingScreen`
and exact `BrainApp` theme in a native iPhone simulator. It supplies the four
user-approved USD prices as display fixtures. It uses no real account, production
network, receipt, transaction, or live StoreKit product query. Purchase and restore
methods deliberately throw in this isolated target.

The first image shows the monthly plan; the second shows the AI GAS packs and
purchase-management controls after an ordinary scroll. Review the images before
uploading them as IAP review screenshots. They document the interface, not working
checkout or verified purchases. Real sandbox transaction testing is still required.

Never sign, archive, upload, or distribute this capture entry point. It does not
change the release branch, production app source, store catalog, or backend flags.
