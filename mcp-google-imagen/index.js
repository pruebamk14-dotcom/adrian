#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import https from "https";
import fs from "fs";

const PUTER_API = "api.puter.com";
const PUTER_TOKEN = process.env.PUTER_TOKEN || "";

function puterImageCall(prompt, model, token) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      interface: "puter-image-generation",
      driver: "ai-image",
      method: "generate",
      args: { prompt, model },
      auth_token: token,
    });

    const options = {
      hostname: PUTER_API,
      path: "/drivers/call",
      method: "POST",
      headers: {
        "Content-Type": "text/plain;actually=json",
        "Content-Length": Buffer.byteLength(body),
      },
    };

    const chunks = [];
    const req = https.request(options, (res) => {
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        const buf = Buffer.concat(chunks);
        // If response looks like JSON error, parse it
        const first = buf[0];
        if (first === 123) { // '{'
          try {
            const json = JSON.parse(buf.toString());
            return reject(new Error(json?.error?.message || JSON.stringify(json)));
          } catch (_) {}
        }
        resolve(buf);
      });
      res.on("error", reject);
    });

    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

const server = new Server(
  { name: "nano-banana-imagen", version: "3.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "generate_image",
      description:
        "Generate images using Google's Nano Banana models (Gemini image generation) for free via Puter.com. Nano Banana 2 = gemini-3.1-flash-image-preview. Requires a free Puter account token.",
      inputSchema: {
        type: "object",
        properties: {
          prompt: {
            type: "string",
            description: "Description of the image to generate",
          },
          model: {
            type: "string",
            enum: [
              "nano-banana",
              "nano-banana-pro",
              "gemini-3.1-flash-image-preview",
              "gemini-3-pro-image-preview",
              "gemini-2.5-flash-image-preview",
            ],
            description:
              "Model to use. 'nano-banana' = Gemini 2.5 Flash Image, 'nano-banana-pro' = Gemini 3 Pro Image. Default: gemini-3.1-flash-image-preview (Nano Banana 2)",
          },
          output_path: {
            type: "string",
            description: "File path to save the image. Defaults to /tmp/nano-banana.png",
          },
        },
        required: ["prompt"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name !== "generate_image") {
    return {
      content: [{ type: "text", text: `Unknown tool: ${request.params.name}` }],
      isError: true,
    };
  }

  if (!PUTER_TOKEN) {
    return {
      content: [
        {
          type: "text",
          text:
            "Error: PUTER_TOKEN is not set.\n\n" +
            "To get a free token:\n" +
            "1. Create a free account at https://puter.com\n" +
            "2. Open browser DevTools (F12) on puter.com\n" +
            "3. Run: localStorage.getItem('puter.auth.token')\n" +
            "4. Add PUTER_TOKEN=<token> to your .claude/settings.local.json env vars",
        },
      ],
      isError: true,
    };
  }

  const {
    prompt,
    model = "gemini-3.1-flash-image-preview",
    output_path = "/tmp/nano-banana.png",
  } = request.params.arguments;

  // Map friendly names to model IDs
  const modelMap = {
    "nano-banana": "gemini-2.5-flash-image-preview",
    "nano-banana-pro": "gemini-3-pro-image-preview",
  };
  const resolvedModel = modelMap[model] || model;

  try {
    const imageBuffer = await puterImageCall(prompt, resolvedModel, PUTER_TOKEN);
    fs.writeFileSync(output_path, imageBuffer);
    const base64 = imageBuffer.toString("base64");

    return {
      content: [
        {
          type: "text",
          text: `Image generated with ${resolvedModel}!\nSaved to: ${output_path}`,
        },
        {
          type: "image",
          data: base64,
          mimeType: "image/png",
        },
      ],
    };
  } catch (err) {
    return {
      content: [{ type: "text", text: `Error: ${err.message}` }],
      isError: true,
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
