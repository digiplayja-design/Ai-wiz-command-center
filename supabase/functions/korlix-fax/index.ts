import { resolveFaxServices, services } from './services.mjs';
import { createHandler } from './handler.mjs';
const env = (name: string) => Deno.env.get(name) ?? '';
const origin = env('FAX_WEB_ORIGIN') || undefined;
const local = createHandler(services(env), origin);
const resolve = resolveFaxServices(env);
Deno.serve(async (request: Request) => {
  const path = new URL(request.url).pathname;
  if (request.method === 'OPTIONS' || /\/(signin|signout|history|file\/[^/]+)$/.test(path))
    return local(request);
  return createHandler(await resolve(), origin)(request);
});
