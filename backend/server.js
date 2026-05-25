import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import OpenAI from "openai";

dotenv.config();

const app = express();
const port = process.env.PORT || 8787;

app.use(cors());
app.use(express.json());

function sanitize(value) {
  const key = process.env.OPENAI_API_KEY || "";
  return String(value || "")
    .replace(key, "[hidden_api_key]")
    .replace(/sk-[A-Za-z0-9_\-]+/g, "sk-[hidden]");
}

app.get("/", (req, res) => {
  res.json({
    status: "AI Wizard backend is running"
  });
});

app.post("/api/generate", async (req, res) => {
  try {
    const command = req.body.command;

    if (!command || command.trim().length === 0) {
      return res.status(400).json({
        error: "Command is required"
      });
    }

    if (!process.env.OPENAI_API_KEY || process.env.OPENAI_API_KEY === "put_your_key_here") {
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
You are AI Wizard Command Center.

The user gave this command:
"${command}"

Create a polished deliverable.

Return:
1. A title
2. A short summary
3. The full generated content
`
    });

    res.json({
      title: "AI Wizard Output",
      content: response.output_text
    });
  } catch (error) {
    const safeMessage = sanitize(error?.message);
    const safeCode = sanitize(error?.code);
    const safeType = sanitize(error?.type);
    const safeStatus = error?.status || 500;

    console.error("OpenAI error:", {
      status: safeStatus,
      code: safeCode,
      type: safeType,
      message: safeMessage
    });

    res.status(500).json({
      error: "AI generation failed",
      status: safeStatus,
      code: safeCode,
      type: safeType,
      details: safeMessage
    });
  }
});

app.listen(port, () => {
  console.log(`AI Wizard backend running on port ${port}`);
});
