"use strict";

const crypto = require("node:crypto");

const {
  K135zZoomError,
} = require(
  "./zoom_token_vault.cjs",
);

function eventObject(body) {
  return (
    body?.payload?.object &&
    typeof body.payload.object ===
      "object"
  )
    ? body.payload.object
    : {};
}

function stableSessionKey(body) {
  const object =
    eventObject(body);

  const meetingUuid =
    String(
      object.uuid ||
        object.meeting_uuid ||
        "",
    ).trim();

  const meetingId =
    String(
      object.id ||
        object.meeting_id ||
        "",
    ).trim();

  const streamId =
    String(
      object.rtms_stream_id ||
        object.stream_id ||
        "",
    ).trim();

  const source = [
    meetingUuid,
    meetingId,
    streamId,
  ]
    .filter(Boolean)
    .join(":");

  if (!source) {
    throw new K135zZoomError(
      400,
      "ZOOM_RTMS_SESSION_IDENTITY_MISSING",
      "The RTMS event has no meeting or stream identity.",
    );
  }

  return crypto
    .createHash("sha256")
    .update(
      source,
      "utf8",
    )
    .digest("hex");
}

class ZoomRtmsSessionManager {
  constructor({
    repository,
    clock = () => Date.now(),
  }) {
    this.repository =
      repository;

    this.clock = clock;
  }

  async handleVerifiedEvent(
    body,
  ) {
    const event =
      String(
        body?.event || "",
      );

    if (
      ![
        "meeting.rtms_started",
        "meeting.rtms_stopped",
        "meeting.rtms_interrupted",
      ].includes(event)
    ) {
      return {
        handled: false,
      };
    }

    const object =
      eventObject(body);

    const sessionKey =
      stableSessionKey(body);

    const status =
      event.endsWith(
        "_started",
      )
        ? "started"
        : event.endsWith(
              "_stopped",
            )
          ? "stopped"
          : "interrupted";

    const record =
      await this.repository
        .upsertRtmsSession(
          sessionKey,
          {
            sessionKey,
            status,
            event,

            eventTs: Number(
              body?.event_ts ||
                this.clock(),
            ),

            meetingId:
              object.id != null
                ? String(
                    object.id,
                  )
                : null,

            meetingUuid:
              object.uuid
                ? String(
                    object.uuid,
                  )
                : null,

            streamId:
              object.rtms_stream_id
                ? String(
                    object.rtms_stream_id,
                  )
                : null,

            stopReason:
              object.stop_reason !=
              null
                ? Number(
                    object.stop_reason,
                  )
                : null,

            updatedAt:
              new Date(
                this.clock(),
              ).toISOString(),

            mediaConnected:
              false,

            transcriptCollected:
              false,

            audioInjected:
              false,
          },
        );

    return {
      handled: true,
      record,
    };
  }
}

module.exports = {
  ZoomRtmsSessionManager,
  eventObject,
  stableSessionKey,
};
