import { api } from "./fax-api.js";

const byId = id => document.getElementById(id);
const signIn = byId("customer-signin");
signIn.append(byId("native-signin-actions").content.cloneNode(true));
document.querySelector(".intro-center h1").textContent = "Your fax workspace";
signIn.querySelector("h2").textContent = "Sign in";
signIn.querySelector("p.sub").textContent = "Use your Korlix account to open your private mailbox.";
byId("try-sample").onclick = () => {
  sessionStorage.setItem("korlixFaxSession", "sample");
  location.replace("./");
};
const registration = byId("customer-registration");
const form = byId("register-form");
const error = byId("register-error");
const guardian = byId("guardian");
const notice = byId("registration-notice");
function showRegistration(open) {
  signIn.hidden = open;
  registration.hidden = !open;
  error.hidden = true;
  byId("new-password").value = "";
  byId("password").value = "";
  (open ? byId("new-email") : byId("email")).focus();
}
byId("create-account").onclick = () => {
  notice.hidden = true;
  byId("new-email").value = byId("email").value;
  showRegistration(true);
};
byId("back-to-signin").onclick = () => showRegistration(false);
byId("age-band").onchange = () => {
  const minor = byId("age-band").value === "16_17";
  byId("guardian-row").hidden = !minor;
  guardian.required = minor;
  if (!minor) guardian.checked = false;
};
form.onsubmit = async event => {
  event.preventDefault();
  error.hidden = true;
  const submit = form.querySelector('button[type="submit"]');
  submit.disabled = true;
  try {
    const age = byId("age-band").value;
    if (age === "under_16") throw Error("You must be at least 16 to create a Korlix account.");
    const email = byId("new-email").value.trim();
    const result = await api("/signup", { method: "POST", anonymous: true, body: {
      email, password: byId("new-password").value,
      signup_eligibility: { age_band: age, terms_accepted: byId("terms-consent").checked,
        privacy_acknowledged: byId("terms-consent").checked, parent_permission: guardian.checked,
        policy_version: "2026-10-06" }
    }});
    form.reset();
    byId("age-band").onchange();
    byId("email").value = email;
    showRegistration(false);
    notice.textContent = result.message;
    notice.hidden = false;
  } catch (e) {
    error.textContent = e.message;
    error.hidden = false;
  } finally {
    submit.disabled = false;
  }
};
