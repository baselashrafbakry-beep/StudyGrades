import { createApp } from "../../src/app.mjs";
import { BlobRepository } from "../../src/blob_repository.mjs";

const repository = new BlobRepository();
const handle = createApp({ repository, env: process.env });

export default async (request) => handle(request);

export const config = {
  path: ["/api/mobile", "/api/mobile/*"],
};
