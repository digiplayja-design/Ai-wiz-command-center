import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const backendServer = readFileSync(
  new URL("./server.js", import.meta.url),
  "utf8",
);

const rootServer = readFileSync(
  new URL("../server.js", import.meta.url),
  "utf8",
);

const agentPersistence = readFileSync(
  new URL("./korlix_live_convo_agents.js", import.meta.url),
  "utf8",
);

const agentModel = readFileSync(
  new URL(
    "../lib/live_convo/korlix_live_convo_agent.dart",
    import.meta.url,
  ),
  "utf8",
);

const agentClient = readFileSync(
  new URL(
    "../lib/live_convo/korlix_live_convo_agent_client.dart",
    import.meta.url,
  ),
  "utf8",
);

const agentSheet = readFileSync(
  new URL(
    "../lib/live_convo/korlix_live_convo_agent_sheet.dart",
    import.meta.url,
  ),
  "utf8",
);

function occurrences(source, value) {
  return source.split(value).length - 1;
}

test(
  "both active servers expose one authenticated training-file route",
  () => {
    const route =
      "/api/live-convo/agents/:agentId/training-files/analyze";

    assert.equal(occurrences(backendServer, route), 1);
    assert.equal(occurrences(rootServer, route), 1);

    for (const source of [backendServer, rootServer]) {
      assert.match(
        source,
        /documentUpload\.array\([\s\S]*?"files"/,
      );

      assert.match(
        source,
        /agentTools\.includes\("agent_training"\)/,
      );

      assert.match(
        source,
        /OPENAI_AGENT_TRAINING_FILE_MODEL/,
      );

      assert.match(
        source,
        /trainingDraft/,
      );
    }
  },
);

test(
  "training-file previews preserve approval and source-retention boundaries",
  () => {
    for (const source of [backendServer, rootServer]) {
      assert.match(
        source,
        /analysisVersion:[\s\S]*?korlix\.agent\.file_training\.preview\.build132\.v1/,
      );

      assert.match(
        source,
        /requiresApproval:[\s\S]*?true/,
      );

      assert.match(
        source,
        /autoSaved:[\s\S]*?false/,
      );

      assert.match(
        source,
        /storedByKorlix:[\s\S]*?false/,
      );

      assert.match(
        source,
        /maximumTrainingCharacters/,
      );
    }
  },
);

test(
  "server-owned training save mode is authoritative",
  () => {
    assert.match(
      agentPersistence,
      /function korlixAgentTrainingModeV1/,
    );

    assert.match(
      agentPersistence,
      /mode === "append"/,
    );

    assert.match(
      agentPersistence,
      /training_mode_invalid/,
    );

    assert.match(
      agentPersistence,
      /User-confirmed training replacement/,
    );
  },
);

test(
  "Flutter contract supports document analysis plus append or replace",
  () => {
    assert.match(
      agentModel,
      /trainingFilesAnalyzePath/,
    );

    assert.match(
      agentModel,
      /'mode': trainingMode/,
    );

    assert.match(
      agentClient,
      /analyzeTrainingFiles/,
    );

    assert.match(
      agentClient,
      /KorlixLiveConvoAgentTrainingFilePreview/,
    );

    assert.match(
      agentClient,
      /agent_training_file_approval_boundary_failed/,
    );

    assert.match(
      agentClient,
      /agent_training_file_retention_boundary_failed/,
    );

    assert.match(
      agentSheet,
      /Upload Training Document/,
    );

    assert.match(
      agentSheet,
      /Choose Training Document/,
    );

    assert.match(
      agentSheet,
      /value: 'append'/,
    );

    assert.match(
      agentSheet,
      /value: 'replace'/,
    );

    assert.match(
      agentSheet,
      /mode: _trainingMode/,
    );
  },
);
