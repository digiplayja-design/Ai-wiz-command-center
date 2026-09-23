import 'funnel_campaign_preparation.dart';
export 'funnel_campaign_preparation.dart' show metaSetupChecks;

Map<String, dynamic> validateMetaPreparation(
  Map<String, dynamic> value,
  String funnel,
  String campaign,
) => validateCampaignPreparation(
  value,
  funnel,
  campaign,
  platform: CampaignSetupPlatform.meta,
);

class FunnelMetaPreparation extends FunnelCampaignPreparation {
  const FunnelMetaPreparation({
    super.key,
    required super.client,
    required super.funnelId,
    required super.campaignId,
    super.scope,
  }) : super(platform: CampaignSetupPlatform.meta);
}
