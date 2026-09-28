// Resume editing is a bounded text operation. Never derive web-search intent
// from private employment history or a pasted job description.
export function resumeTextPolicy(body) {
  return body?.purpose === 'resume_studio'
    ? { liveSearchNeeded: false, fileRequested: false }
    : null;
}
