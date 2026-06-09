#!/usr/bin/env node
import { GoogleGenAI } from "@google/genai";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import fs from "fs";
import path from "path";

const API_KEY = process.env.GEMINI_API_KEY;

const server = new Server(
  { name: "google-imagen", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "generate_image",
      description:
        "Generate an image using Google Gemini (Imagen / Nano Banana Pro model from labs.google). Returns the image saved to disk and its base64 data.",
      inputSchema: {
        type: "object",
        properties: {
          prompt: {
            type: "string",
            description: "Description of the image to generate",
          },
          output_path: {
            type: "string",
            description:
              "Optional file path to save the image (e.g. /tmp/image.png). Defaults to /tmp/gemini-image.png",
          },
          aspect_ratio: {
            type: "string",
            enum: ["1:1", "16:9", "9:16", "4:3", "3:4"],
            description: "Aspect ratio of the generated image. Default: 1:1",
          },
        },
        required: ["prompt"],
      },
    },
    {
      name: "edit_image",
      description:
        "Edit or transform an existing image using Google Gemini with a text instruction.",
      inputSchema: {
        type: "object",
        properties: {
          prompt: {
            type: "string",
            description: "Instruction for how to edit the image",
          },
          image_path: {
            type: "string",
            description: "Path to the input image file",
          },
          output_path: {
            type: "string",
            description: "Optional path to save the result. Defaults to /tmp/gemini-edited.png",
          },
        },
        required: ["prompt", "image_path"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (!API_KEY) {
    return {
      content: [
        {
          type: "text",
          text: "Error: GEMINI_API_KEY environment variable is not set. Get a free key at https://aistudio.google.com/apikey",
        },
      ],
      isError: true,
    };
  }

  const ai = new GoogleGenAI({ apiKey: API_KEY });

  if (request.params.name === "generate_image") {
    const { prompt, output_path, aspect_ratio } = request.params.arguments;
    const outPath = output_path || "/tmp/gemini-image.png";

    try {
      const response = await ai.models.generateContent({
        model: "gemini-2.0-flash-preview-image-generation",
        contents: prompt,
        config: {
          responseModalities: ["TEXT", "IMAGE"],
          ...(aspect_ratio && { aspectRatio: aspect_ratio }),
        },
      });

      let imageData = null;
      let textResponse = "";

      for (const part of response.candidates[0].content.parts) {
        if (part.text) {
          textResponse = part.text;
        } else if (part.inlineData) {
          imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync(outPath, buffer);
        }
      }

      if (!imageData) {
        return {
          content: [{ type: "text", text: "No image was generated. " + textResponse }],
          isError: true,
        };
      }

      return {
        content: [
          {
            type: "text",
            text: `Image generated successfully!\nSaved to: ${outPath}\n${textResponse ? "\nModel note: " + textResponse : ""}`,
          },
          {
            type: "image",
            data: imageData,
            mimeType: "image/png",
          },
        ],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Generation error: ${err.message}` }],
        isError: true,
      };
    }
  }

  if (request.params.name === "edit_image") {
    const { prompt, image_path, output_path } = request.params.arguments;
    const outPath = output_path || "/tmp/gemini-edited.png";

    try {
      if (!fs.existsSync(image_path)) {
        return {
          content: [{ type: "text", text: `File not found: ${image_path}` }],
          isError: true,
        };
      }

      const imageBuffer = fs.readFileSync(image_path);
      const base64Image = imageBuffer.toString("base64");
      const ext = path.extname(image_path).toLowerCase();
      const mimeMap = { ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp" };
      const mimeType = mimeMap[ext] || "image/png";

      const response = await ai.models.generateContent({
        model: "gemini-2.0-flash-preview-image-generation",
        contents: [
          {
            parts: [
              { text: prompt },
              { inlineData: { mimeType, data: base64Image } },
            ],
          },
        ],
        config: { responseModalities: ["TEXT", "IMAGE"] },
      });

      let imageData = null;
      let textResponse = "";

      for (const part of response.candidates[0].content.parts) {
        if (part.text) textResponse = part.text;
        else if (part.inlineData) {
          imageData = part.inlineData.data;
          fs.writeFileSync(outPath, Buffer.from(imageData, "base64"));
        }
      }

      if (!imageData) {
        return {
          content: [{ type: "text", text: "No image returned. " + textResponse }],
          isError: true,
        };
      }

      return {
        content: [
          { type: "text", text: `Image edited successfully!\nSaved to: ${outPath}` },
          { type: "image", data: imageData, mimeType: "image/png" },
        ],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Edit error: ${err.message}` }],
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
