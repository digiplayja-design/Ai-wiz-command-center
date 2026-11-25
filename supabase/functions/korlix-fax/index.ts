import { services } from './services.mjs';
import { createHandler } from './handler.mjs';
const env = (name: string) => Deno.env.get(name) ?? '';
Deno.serve(createHandler(services(env), env('FAX_WEB_ORIGIN') || undefined));
