#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import https from "https";
import fs from "fs";

const POLLINATIONS_URL = "https://image.pollinations.ai/prompt/";

function fetchImage(url) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    https.get(url, { headers: { "User-Agent": "mcp-pollinations/1.0" } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return fetchImage(res.headers.location).then(resolve).catch(reject);
      }
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => resolve(Buffer.concat(chunks)));
      res.on("error", reject);
    }).on("error", reject);
  });
}

const server = new Server(
  { name: "pollinations-imagen", version: "2.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "generate_image",
      description:
        "Generate an image for free using Pollinations.ai (no API key needed). Supports multiple models including flux, turbo, gptimage, and more.",
      inputSchema: {
        type: "object",
        properties: {
          prompt: {
            type: "string",
            description: "Description of the image to generate",
          },
          output_path: {
            type: "string",
            description: "File path to save the image. Defaults to /tmp/pollinations-image.png",
          },
          width: {
            type: "number",
            description: "Image width in pixels (default: 1024)",
          },
          height: {
            type: "number",
            description: "Image height in pixels (default: 1024)",
          },
          model: {
            type: "string",
            enum: ["flux", "flux-realism", "flux-anime", "flux-3d", "turbo", "gptimage"],
            description: "Model to use. Default: flux",
          },
          seed: {
            type: "number",
            description: "Seed for reproducible results",
          },
          enhance: {
            type: "boolean",
            description: "Enhance prompt automatically (default: false)",
          },
        },
        required: ["prompt"],
      },
    },
    {
      name: "list_models",
      description: "List all available free image generation models from Pollinations.ai",
      inputSchema: { type: "object", properties: {} },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name === "list_models") {
    return {
      content: [
        {
          type: "text",
          text: `Available free models on Pollinations.ai:\n\n- flux (default) — High quality, general purpose\n- flux-realism — Photorealistic images\n- flux-anime — Anime/manga style\n- flux-3d — 3D rendered style\n- turbo — Faster generation\n- gptimage — GPT-based image generation`,
        },
      ],
    };
  }

  if (request.params.name === "generate_image") {
    const {
      prompt,
      output_path,
      width = 1024,
      height = 1024,
      model = "flux",
      seed,
      enhance = false,
    } = request.params.arguments;

    const outPath = output_path || "/tmp/pollinations-image.png";

    try {
      const encodedPrompt = encodeURIComponent(prompt);
      const params = new URLSearchParams({
        width: width.toString(),
        height: height.toString(),
        model,
        nologo: "true",
        enhance: enhance.toString(),
        ...(seed !== undefined && { seed: seed.toString() }),
      });

      const url = `${POLLINATIONS_URL}${encodedPrompt}?${params}`;

      const imageBuffer = await fetchImage(url);
      fs.writeFileSync(outPath, imageBuffer);

      const base64 = imageBuffer.toString("base64");

      return {
        content: [
          {
            type: "text",
            text: `Image generated successfully!\nModel: ${model}\nSize: ${width}x${height}\nSaved to: ${outPath}`,
          },
          {
            type: "image",
            data: base64,
            mimeType: "image/jpeg",
          },
        ],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Error generating image: ${err.message}` }],
        isError: true,
      };
    }
  }

  return {
    content: [{ type: "text", text: `Unknown tool: ${request.params.name}` }],
    isError: true,
  };
});

const transport = new StdioServerTransport();
await server.connect(transport);
