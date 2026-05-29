import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import OpenAI from "openai";

dotenv.config();

const app = express();
const port = process.env.PORT || 8787;

app.use(cors());
app.use(express.json({ limit: "5mb" }));

function sanitize(value) {
  const openAiKey = process.env.OPENAI_API_KEY || "";

  return String(value || "")
    .replace(openAiKey, "[hidden_openai_key]")
    .replace(/sk-[A-Za-z0-9_\-]+/g, "sk-[hidden]");
}

const languageMap = {
  en: {
    name: "English",
    instruction: "Respond in polished English."
  },
  es: {
    name: "Spanish",
    instruction: "Respond in natural, polished Spanish."
  },
  fr: {
    name: "French",
    instruction: "Respond in natural, polished French."
  }
};

function shouldUseLiveSearch(command) {
  const lower = String(command || "").toLowerCase();

  const liveKeywords = [
    "current",
    "today",
    "now",
    "latest",
    "recent",
    "2026",
    "this year",
    "news",
    "score",
    "standings",
    "stats",
    "ranking",
    "rankings",
    "best team",
    "nba",
    "basketball",
    "football",
    "soccer",
    "baseball",
    "stock",
    "price",
    "weather",
    "president",
    "ceo",
    "trending"
  ];

  return liveKeywords.some((word) => lower.includes(word));
}

function wantsFile(command) {
  const lower = String(command || "").toLowerCase();

  const fileWords = [
    "pdf",
    "word",
    "docx",
    "document",
    "download",
    "export",
    "file",
    "printable",
    "save as",
    "archivo",
    "documento",
    "exportar",
    "descargar",
    "imprimible",
    "fichier",
    "document",
    "exporter",
    "télécharger",
    "imprimable"
  ];

  return fileWords.some((word) => lower.includes(word));
}

async function createResponse(client, { model, input, useSearch }) {
  const request = {
    model,
    input
  };

  if (useSearch) {
    request.tools = [{ type: "web_search" }];
    request.tool_choice = "required";
  }

  return client.responses.create(request);
}

app.get("/", (req, res) => {
  res.json({
    status: "Chee Chai Chee backend is running"
  });
});

app.post("/api/generate", async (req, res) => {
  try {
    const command = req.body.command;
    const languageCode = req.body.language || "en";
    const language = languageMap[languageCode] || languageMap.en;
    const liveSearchNeeded = shouldUseLiveSearch(command);
    const fileRequested = wantsFile(command);

    if (!command || command.trim().length === 0) {
      return res.status(400).json({
        error: "Command is required"
      });
    }

    if (!process.env.OPENAI_API_KEY) {
      return res.status(400).json({
        error: "Missing OPENAI_API_KEY in backend/.env"
      });
    }

    const client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY
    });

    const normalModel = process.env.OPENAI_MODEL || "gpt-5.4-mini";
    const searchModel = process.env.OPENAI_SEARCH_MODEL || normalModel;

    const modeInstruction = fileRequested
      ? `
The user requested a file/document-style output.
Create a polished deliverable with clean sections, practical details, and strong structure.
`
      : `
The user did not request a PDF, file, or document.
Answer like a premium AI assistant, not like a document generator.
Do not use generic sections like Overview, Step-by-Step Plan, Common Mistakes, or Next Move unless they truly fit the question.
For a normal question, give:
1. Direct answer
2. Why
3. Best options or contenders when useful
4. Final verdict
`;

    const searchInstruction = liveSearchNeeded
      ? `
This question needs current information.
Use live web search.
Bring up real contenders, recent data, standings, rankings, current performance, or relevant sources when useful.
For sports questions, do not dodge. Give a best pick or ranked shortlist and explain the evidence.
`
      : `
This question does not require live search unless the user explicitly asks for current information.
`;

    const input = `
You are Chee Chai Chee, a premium multilingual AI assistant inside a productivity app.

You are not just a PDF maker.
You are not a search engine.
You are not a generic chatbot.

The user selected this language:
${language.name}

Language rule:
${language.instruction}

The user wrote:
"${command}"

${modeInstruction}

${searchInstruction}

Answer quality rules:
- Be direct.
- Be useful.
- Give judgment when the user asks for judgment.
- For "best" questions, do not hide behind vague wording.
- If there is no single answer, give the top contenders and your final pick.
- Use real evidence when available.
- Avoid filler.
- Avoid generic chatbot disclaimers.
- Avoid ending with "If you want".
- Do not mention PDF unless the user asked for a file or PDF.

Formatting rules:
- Use plain text only.
- Do not use markdown symbols like **bold**, ###, checkboxes, or emojis.
- Do not use strange symbols.
- Use short headings only when helpful.
- Use numbered lists for rankings or steps.
- Use hyphen bullets only when needed.

Return only the finished response.
`;

    let response;
    let searched = false;
    let fallbackUsed = false;

    if (liveSearchNeeded) {
      try {
        response = await createResponse(client, {
          model: searchModel,
          input,
          useSearch: true
        });
        searched = true;
      } catch (searchError) {
        console.error("Live search failed, falling back:", sanitize(searchError?.message));

        response = await createResponse(client, {
          model: normalModel,
          input: `${input}

Important: Live search was attempted but failed. Give the most useful answer possible and clearly avoid pretending to know live standings.`,
          useSearch: false
        });

        fallbackUsed = true;
      }
    } else {
      response = await createResponse(client, {
        model: normalModel,
        input,
        useSearch: false
      });
    }

    res.json({
      title: "Chee Chai Chee Output",
      language: languageCode,
      searched,
      fallbackUsed,
      fileRequested,
      content: response.output_text
    });
  } catch (error) {
    console.error("OpenAI error:", sanitize(error?.message));

    res.status(500).json({
      error: "AI generation failed",
      details: sanitize(error?.message)
    });
  }
});

app.listen(port, () => {
  console.log(`Chee Chai Chee backend running on port ${port}`);
});
