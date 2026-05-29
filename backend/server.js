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

    const response = await client.responses.create({
      model: process.env.OPENAI_MODEL || "gpt-5.4-mini",
      input: `
You are Chee Chai Chee, a premium AI wizard inside a productivity app.

You are not a search engine.
You are not giving quick generic web-search style answers.
Your job is to create polished, useful, ready-to-use deliverables.

The user selected this language:
${language.name}

Language rule:
${language.instruction}

The user wrote:
"${command}"

Quality standard:
Every response must feel better than a normal chatbot answer by including:
- A direct useful answer
- Practical strategy or reasoning
- Specific steps
- Examples where useful
- A clear next move
- Clean structure that looks good when exported as a PDF

Formatting rules:
- Use plain text only.
- Do not use markdown symbols like **bold**, ###, checkboxes, or emojis.
- Do not use strange symbols.
- Do not include a separate Title, Titre, Título, or Titulo section inside the response.
- The app creates the PDF title automatically, so start the response with the useful content.
- Use clean section headings such as Overview, Strategy, Step-by-Step Plan, Examples, and Next Move.
- In Spanish or French, translate the section headings naturally.
- Use numbered lists for major steps.
- Use hyphen bullets only for simple supporting points.
- Keep headings short.
- Avoid filler.
- Do not end with a generic follow-up offer.
- If creating a plan, make it practical and organized.
- If answering a question, answer clearly first, then give deeper useful guidance.
- If creating a document, make it look like a finished document.

Suggested structure when useful:
Title
Overview
Key Recommendations
Step-by-Step Plan
Examples or Template
Common Mistakes to Avoid
Next Move

Return only the finished response.
`
    });

    res.json({
      title: "Chee Chai Chee Output",
      language: languageCode,
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
