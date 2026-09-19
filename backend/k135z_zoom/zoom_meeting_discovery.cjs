"use strict";

const {
  K135zZoomError,
} = require(
  "./zoom_token_vault.cjs",
);

function safeString(
  value,
  maximum = 240,
) {
  return String(
    value ?? "",
  )
    .trim()
    .slice(
      0,
      maximum,
    );
}

function normalizeMeeting(raw) {
  if (
    !raw ||
    typeof raw !== "object" ||
    raw.id == null
  ) {
    return null;
  }

  return {
    id: String(raw.id),

    uuid:
      raw.uuid
        ? safeString(
            raw.uuid,
            180,
          )
        : null,

    topic: safeString(
      raw.topic ||
        "Untitled meeting",
      300,
    ),

    startTime:
      raw.start_time
        ? safeString(
            raw.start_time,
            80,
          )
        : null,

    durationMinutes:
      Number.isFinite(
        Number(
          raw.duration,
        ),
      )
        ? Number(
            raw.duration,
          )
        : null,

    timezone:
      raw.timezone
        ? safeString(
            raw.timezone,
            100,
          )
        : null,

    type:
      Number.isFinite(
        Number(raw.type),
      )
        ? Number(raw.type)
        : null,

    isHost:
      Boolean(raw.is_host),

    isAllDay:
      Boolean(raw.is_all_day),

    source: "zoom",
  };
}

class ZoomMeetingDiscovery {
  constructor({
    oauthService,
    transport,
    maximumMeetings = 100,
  }) {
    this.oauthService =
      oauthService;

    this.transport =
      transport;

    this.maximumMeetings =
      maximumMeetings;
  }

  async listUpcoming(
    principal,
  ) {
    const authorization =
      await this.oauthService
        .getAuthorizedAccess(
          principal,
        );

    if (
      typeof this.transport
        .listUpcomingMeetings !==
      "function"
    ) {
      throw new K135zZoomError(
        503,
        "ZOOM_MEETING_DISCOVERY_DISABLED",
        "Zoom meeting discovery is unavailable.",
      );
    }

    const response =
      await this.transport
        .listUpcomingMeetings({
          accessToken:
            authorization
              .accessToken,
          apiUrl:
            authorization.apiUrl,
          userId: "me",
        });

    const rawMeetings =
      Array.isArray(
        response?.meetings,
      )
        ? response.meetings
        : [];

    const meetings =
      rawMeetings
        .map(normalizeMeeting)
        .filter(Boolean)
        .slice(
          0,
          this.maximumMeetings,
        );

    return {
      meetings,
      count: meetings.length,

      nextPageToken:
        response?.next_page_token
          ? safeString(
              response.next_page_token,
              300,
            )
          : null,
    };
  }
}

module.exports = {
  ZoomMeetingDiscovery,
  normalizeMeeting,
};
