// Fixed browser enhancement: no user text is interpolated into executable code.
// The response CSP allows only the hash of this exact script.
export function enhanceQuestions(document) {
  for (const form of document.querySelectorAll('form[data-conditional-questions]')) {
    const refresh = () => {
      const active = new Map();
      for (const group of form.querySelectorAll('[data-question-id]')) {
        const field = group.querySelector('select,textarea');
        const parent = group.dataset.showQuestion;
        const source = active.get(parent);
        const show = !parent || (source && source.tagName === 'SELECT' && source.value.trim() === group.dataset.showValue);
        group.hidden = !show;
        field.disabled = !show;
        field.required = !!show && group.dataset.required === 'true';
        if (show) active.set(group.dataset.questionId, field);
        else field.value = ''; // Do not restore a discarded branch on a later change.
      }
    };
    form.addEventListener('change', refresh);
    refresh();
    const fallback = form.querySelector('[data-update-questions]');
    if (fallback) fallback.hidden = true;
  }
}
export const questionScript = `(${enhanceQuestions.toString()})(document);`;
