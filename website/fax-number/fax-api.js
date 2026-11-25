export const origin = "https://uxtjzjbwtppjvnsoiijv.supabase.co";
const endpoint = origin + "/functions/v1/korlix-fax";
const key = "korlixFaxSession";
export const currentSession = () => sessionStorage.getItem(key);
export function openLogin(message = "") {
  sessionStorage.removeItem(key);
  if (message) sessionStorage.setItem("korlixFaxNotice", message);
  location.replace("account.html?return=workspace");
}
export function phoneNumber(value) {
  if (typeof value !== "string" || !/^[\d+()\s.-]+$/.test(value)) return "";
  let digits = value.replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) digits = digits.slice(1);
  return /^[2-9]\d{2}[2-9]\d{6}$/.test(digits) ? "+1" + digits : "";
}
export const displayNumber = (n) =>
  String(n || "").replace(/^\+1(\d{3})(\d{3})(\d{4})$/, "($1) $2-$3");
export async function api(
  path,
  { method = "GET", body, headers = {}, raw = false, anonymous = false } = {},
) {
  const token = currentSession();
  const h = new Headers(headers);
  if (token && !anonymous) h.set("x-fax-session", token);
  if (body !== undefined && !raw) h.set("content-type", "application/json");
  let response;
  try {
    response = await fetch(endpoint + path, {
      headers: h,
      method,
      body: body === undefined ? undefined : raw ? body : JSON.stringify(body),
      cache: "no-store",
      referrerPolicy: "no-referrer",
      credentials: "omit",
      redirect: "error",
      signal: AbortSignal.timeout(raw ? 65000 : 30000),
    });
  } catch {
    throw Error(
      "Could not reach the fax service. Check your connection and try again.",
    );
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 403 && path === "/workspace" && token === currentSession())
      openLogin(data.error || "This workspace is for Korlix company use only.");
    if (
      response.status === 401 &&
      !anonymous &&
      token &&
      token === currentSession()
    )
      openLogin("Your fax session ended. Sign in again.");
    throw Object.assign(
      Error(data.error || "The fax service could not complete this request."),
      { status: response.status },
    );
  }
  return data;
}
export async function redeem(code) {
  let device = localStorage.getItem("korlixFaxDevice");
  if (!device) {
    device = crypto.randomUUID();
    localStorage.setItem("korlixFaxDevice", device);
  }
  const { token } = await api("/redeem", {
    method: "POST",
    body: { code, device },
    anonymous: true,
  });
  if (!/^[a-f0-9]{64}$/.test(token))
    throw Error("Korlix could not open this fax workspace.");
  sessionStorage.setItem(key, token);
}
export function checkFileUrl(url) {
  const target = new URL(url);
  if (
    target.origin !== origin ||
    !target.pathname.startsWith("/storage/v1/object/sign/korlix-fax-documents/")
  )
    throw Error("The document link is unavailable.");
  return target.href;
}
export async function dispatch(doc, recipient, owner) {
  const bytes = await doc.file.arrayBuffer();
  const hash = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (x) => x.toString(16).padStart(2, "0"),
  ).join("");
  const pending = "faxPending:" + owner + ":" + recipient + ":" + hash;
  const id = sessionStorage.getItem(pending) || crypto.randomUUID();
  sessionStorage.setItem(pending, id);
  const result = await api("/send", {
    method: "POST",
    raw: true,
    body: doc.file,
    headers: {
      "Content-Type": "application/pdf",
      "X-Fax-To": recipient,
      "X-Request-ID": id,
      "X-Filename": encodeURIComponent(doc.name.slice(0, 120)),
    },
  });
  if (!result.id)
    throw Error("Check Sent for a delivery update before retrying.");
  sessionStorage.removeItem(pending);
  return result;
}
