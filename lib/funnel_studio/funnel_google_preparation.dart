import 'funnel_campaign_preparation.dart';
export 'funnel_campaign_preparation.dart' show googleSetupChecks;

Map<String, dynamic> validateGooglePreparation(
  Map<String, dynamic> value,
  String funnel,
  String campaign,
) => validateCampaignPreparation(
  value,
  funnel,
  campaign,
  platform: CampaignSetupPlatform.google,
);

class FunnelGooglePreparation extends FunnelCampaignPreparation {
  const FunnelGooglePreparation({
    super.key,
    required super.client,
    required super.funnelId,
    required super.campaignId,
    super.scope,
  }) : super(platform: CampaignSetupPlatform.google);
}
