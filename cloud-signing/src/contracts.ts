import { z } from 'zod';
export const uuid = z.uuid();
export const signRequest = z.object({
  ipaId: uuid, p12Id: uuid, provisionId: uuid,
  password: z.string().max(1024), webhook: z.url().max(2048).optional(),
}).strict();
export const checkRequest = signRequest.omit({ ipaId: true });
export const batchRequest = z.object({ jobs: z.array(signRequest.extend({ idempotencyKey: uuid })).min(1).max(20) }).strict();
export type SignRequest = z.infer<typeof signRequest>;
export const artifactMetadata = z.object({
  name: z.string().min(1).max(200),
  bundleIdentifier: z.string().regex(/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/).max(255),
  version: z.string().min(1).max(100),
  changelog: z.string().max(20_000).default(''),
  iconURL: z.url().refine(v => new URL(v).protocol === 'https:').optional(),
  screenshotURLs: z.array(z.url().refine(v => new URL(v).protocol === 'https:')).max(10).default([]),
}).strict();
export type ArtifactMetadata = z.infer<typeof artifactMetadata>;
export const certificateResult = z.object({
  status: z.enum(['good', 'revoked', 'unknown']),
  checkedAt: z.iso.datetime(), teamID: z.string().max(100), teamName: z.string().max(300),
  expiresAt: z.iso.datetime(), detail: z.string().max(2000),
}).strict();
